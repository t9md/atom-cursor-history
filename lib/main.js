const {CompositeDisposable, Disposable} = require("atom")
const DefaultIgnoreCommands = [
  "cursor-history:next",
  "cursor-history:prev",
  "cursor-history:next-within-editor",
  "cursor-history:prev-within-editor",
  "cursor-history:clear",
]

const closestTextEditorHavingURI = function(target) {
  if (!target || !target.closest("atom-text-editor")) return
  const editor = target.closest("atom-text-editor").getModel()
  if (editor && editor.getURI()) {
    return editor
  }
}

function createLocation(editor, type) {
  return {
    type,
    editor,
    point: editor.getCursorBufferPosition(),
    URI: editor.getURI(),
  }
}

module.exports = {
  serialize() {
    return {
      history: this.history ? this.history.serialize() : this.restoredState.history,
    }
  },

  activate(restoredState) {
    this.restoredState = restoredState
    this.subscriptions = new CompositeDisposable()
    this.locationCheckTimeoutID = null

    const jump = (...args) => this.getHistory().jump(...args)

    this.subscriptions.add(
      atom.commands.add("atom-text-editor", {
        "cursor-history:next"() {
          jump(this.getModel(), "next")
        },
        "cursor-history:prev"() {
          jump(this.getModel(), "prev")
        },
        "cursor-history:next-within-editor"() {
          jump(this.getModel(), "next", {withinEditor: true})
        },
        "cursor-history:prev-within-editor"() {
          jump(this.getModel(), "prev", {withinEditor: true})
        },
        "cursor-history:clear": () => this.history && this.history.clear(),
        "cursor-history:toggle-debug": () => this.toggleDebug(),
      })
    )

    this.observeMouse()
    this.observeCommands()
    this.subscriptions.add(
      atom.config.observe("cursor-history.ignoreCommands", newValue => {
        this.ignoreCommands = DefaultIgnoreCommands.concat(newValue)
      })
    )
  },

  toggleDebug() {
    const newValue = !atom.config.get("cursor-history.debug")
    atom.config.set("cursor-history.debug", newValue)
    console.log("debug: ", newValue)
  },

  deactivate() {
    clearTimeout(this.locationCheckTimeoutID)
    this.subscriptions.dispose()
    if (this.history) this.history.destroy()
    this.subscriptions = this.history = this.locationCheckTimeoutID = null
  },

  getHistory() {
    if (!this.history) {
      History = require("./history")
      this.history = (this.restoredState ? this.restoredState.history : undefined)
        ? History.deserialize(this.restoredState.history)
        : new History()
    }

    return this.history
  },

  // When mouse clicked, cursor position is updated by atom core using setCursorScreenPosition()
  // To track cursor position change caused by mouse click, I use mousedown event.
  //  - Event capture phase: Cursor position is not yet changed.
  //  - Event bubbling phase: Cursor position updated to clicked position.
  observeMouse() {
    const locationStack = []

    const checkLocationChangeAfter = (location, timeout) => {
      clearTimeout(this.locationCheckTimeoutID)
      this.locationCheckTimeoutID = setTimeout(() => {
        this.checkLocationChange(location)
      }, timeout)
    }

    const handleCapture = function(event) {
      const editor = closestTextEditorHavingURI(event.target)
      if (editor) {
        // In case, mousedown event was not **bubbled** up, detect location change
        // by comparing old and new location after 300ms
        // This task is cancelled when mouse event bubbled up to avoid duplicate
        // location check.
        //
        // E.g. hyperclick package open another file by mouseclick, it explicitly
        // call `event.stopPropagation()` to prevent default mouse behavior of Atom.
        // In such case we can't catch mouseclick event at bublling phase.
        const location = createLocation(editor, "mousedown")
        locationStack.push(location)
        checkLocationChangeAfter(location, 300)
      }
    }

    const handleBubble = event => {
      clearTimeout(this.locationCheckTimeoutID)
      const location = locationStack.pop()
      if (location) setTimeout(() => this.checkLocationChange(location), 100)
    }

    const workspaceElement = atom.views.getView(atom.workspace)
    workspaceElement.addEventListener("mousedown", handleCapture, true)
    workspaceElement.addEventListener("mousedown", handleBubble, false)

    this.subscriptions.add(
      new Disposable(function() {
        workspaceElement.removeEventListener("mousedown", handleCapture, true)
        workspaceElement.removeEventListener("mousedown", handleBubble, false)
      })
    )
  },

  observeCommands() {
    let trackLocationTimeout
    const locationStack = []
    this.locationStackForTestSpec = locationStack // expose to make test easy

    const isInterestingCommand = type => {
      return type.includes(":") && !this.ignoreCommands.includes(type)
    }

    const resetTrackingDelay = function() {
      clearTimeout(trackLocationTimeout)
      trackLocationTimeout = null
    }

    const trackLocationChangeEdgeDebounced = function(type, editor) {
      if (trackLocationTimeout) {
        resetTrackingDelay()
      } else {
        locationStack.push(createLocation(editor, type))
      }
      trackLocationTimeout = setTimeout(resetTrackingDelay, 100)
    }

    const disposableForWillDispatch = atom.commands.onWillDispatch(({type, target}) => {
      if (!isInterestingCommand(type)) return
      const editor = closestTextEditorHavingURI(target)
      if (editor) trackLocationChangeEdgeDebounced(type, editor)
    })

    const disposableForDidDispatch = atom.commands.onDidDispatch(({type, target}) => {
      if (!locationStack.length) return
      if (!isInterestingCommand(type)) return
      if (closestTextEditorHavingURI(target)) {
        // To wait cursor position is set on final destination.
        setTimeout(() => {
          this.checkLocationChange(locationStack.pop())
        }, 100)
      }
    })

    this.subscriptions.add(disposableForWillDispatch, disposableForDidDispatch)
  },

  checkLocationChange(oldLocation) {
    if (oldLocation == null) return

    const editor = atom.workspace.getActiveTextEditor()
    if (!editor) return

    if (!editor.element.hasFocus() || editor.getURI() !== oldLocation.URI) {
      this.getHistory().add(oldLocation, {message: `Save on focus lost [${oldLocation.type}]`})
      return
    }

    // Move within same buffer.
    const oldPoint = oldLocation.point
    const newPoint = editor.getCursorBufferPosition()
    const {row, column} = oldPoint.isGreaterThan(newPoint)
      ? oldPoint.traversalFrom(newPoint)
      : newPoint.traversalFrom(oldPoint)

    if (
      row > atom.config.get("cursor-history.rowDeltaToRemember") ||
      (row === 0 && column > atom.config.get("cursor-history.columnDeltaToRemember"))
    ) {
      this.getHistory().add(oldLocation, {message: `Cursor moved [${oldLocation.type}]`})
    }
  },
}
