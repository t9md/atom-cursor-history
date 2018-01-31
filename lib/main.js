const {CompositeDisposable, Disposable} = require('atom')
const DefaultIgnoreCommands = [
  'cursor-history:next',
  'cursor-history:prev',
  'cursor-history:next-within-editor',
  'cursor-history:prev-within-editor',
  'cursor-history:clear'
]

function getClosestEditorForTarget (target) {
  if (!target || !target.closest('atom-text-editor')) return
  const editor = target.closest('atom-text-editor').getModel()
  if (!editor.isMini()) return editor
}

function createLocation (editor, command) {
  return {
    command,
    editor,
    point: editor.getCursorBufferPosition(),
    URI: editor.getURI()
  }
}

module.exports = {
  serialize () {
    return {
      history: this.history ? this.history.serialize() : this.restoredState.history
    }
  },

  activate (restoredState) {
    this.restoredState = restoredState
    this.subscriptions = new CompositeDisposable()
    this.locationCheckTimeoutID = null

    const jump = (...args) => this.getHistory().jump(...args)

    this.subscriptions.add(
      atom.commands.add('atom-text-editor', {
        'cursor-history:next' () {
          jump(this.getModel(), 'next')
        },
        'cursor-history:prev' () {
          jump(this.getModel(), 'prev')
        },
        'cursor-history:next-within-editor' () {
          jump(this.getModel(), 'next', {withinEditor: true})
        },
        'cursor-history:prev-within-editor' () {
          jump(this.getModel(), 'prev', {withinEditor: true})
        },
        'cursor-history:dump-history': () => {
          this.getHistory().log('DUMP')
        },
        'cursor-history:clear': () => this.history && this.history.clear(),
        'cursor-history:toggle-debug': () => this.toggleDebug()
      })
    )

    this.observeMouse()
    this.observeCommands()

    this.subscriptions.add(
      atom.config.observe('cursor-history.ignoreCommands', newValue => {
        this.ignoreCommands = DefaultIgnoreCommands.concat(newValue)
      }),
      atom.config.observe('cursor-history.rowDeltaToRemember', newValue => {
        this.rowDeltaToRemember = newValue
      }),
      atom.config.observe('cursor-history.columnDeltaToRemember', newValue => {
        this.columnDeltaToRemember = newValue
      })
    )
  },

  toggleDebug () {
    const newValue = !atom.config.get('cursor-history.debug')
    atom.config.set('cursor-history.debug', newValue)
    console.log('debug: ', newValue)
  },

  deactivate () {
    clearTimeout(this.locationCheckTimeoutID)
    this.subscriptions.dispose()
    if (this.history) this.history.destroy()
    this.subscriptions = this.history = this.locationCheckTimeoutID = null
  },

  getHistory () {
    if (!this.history) {
      const History = require('./history')
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
  observeMouse () {
    const locationStack = []

    const checkLocationChangeAfter = (location, timeout) => {
      clearTimeout(this.locationCheckTimeoutID)
      this.locationCheckTimeoutID = setTimeout(() => {
        this.checkLocationChange(location)
      }, timeout)
    }

    const handleCapture = function (event) {
      const editor = getClosestEditorForTarget(event.target)
      if (editor) {
        // In case, mousedown event was not **bubbled** up, detect location change
        // by comparing old and new location after 300ms
        // This task is cancelled when mouse event bubbled up to avoid duplicate
        // location check.
        //
        // E.g. hyperclick package open another file by mouseclick, it explicitly
        // call `event.stopPropagation()` to prevent default mouse behavior of Atom.
        // In such case we can't catch mouseclick event at bublling phase.
        const location = createLocation(editor, 'mousedown')
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
    workspaceElement.addEventListener('mousedown', handleCapture, true)
    workspaceElement.addEventListener('mousedown', handleBubble, false)

    this.subscriptions.add(
      new Disposable(function () {
        workspaceElement.removeEventListener('mousedown', handleCapture, true)
        workspaceElement.removeEventListener('mousedown', handleBubble, false)
      })
    )
  },

  observeCommands () {
    let trackThrottlingTimeout
    const locationStack = []
    this.locationStackForTestSpec = locationStack // expose to make test easy

    const isInterestingCommand = type => type.includes(':') && !this.ignoreCommands.includes(type)

    const clearThrottling = function () {
      clearTimeout(trackThrottlingTimeout)
      trackThrottlingTimeout = null
    }

    this.subscriptions.add(
      atom.commands.onWillDispatch(({type, target}) => {
        if (!isInterestingCommand(type)) return
        const editor = getClosestEditorForTarget(target)
        if (editor) {
          if (!trackThrottlingTimeout) {
            locationStack.push(createLocation(editor, type))
          }
          trackThrottlingTimeout = setTimeout(clearThrottling, 100)
        }
      }),
      atom.commands.onDidDispatch(({type, target}) => {
        if (!locationStack.length) return
        if (!isInterestingCommand(type)) return
        if (getClosestEditorForTarget(target)) {
          // To wait cursor position is set on final destination.
          setTimeout(() => {
            this.checkLocationChange(locationStack.pop())
          }, 100)
        }
      })
    )
  },

  checkLocationChange (oldLocation) {
    if (oldLocation == null) return

    const editor = atom.workspace.getActiveTextEditor()
    if (!editor) return

    const {URI: oldURI, point: oldPoint, editor: oldEditor} = oldLocation
    if (!editor.element.hasFocus() || (oldURI ? editor.getURI() !== oldURI : editor !== oldEditor)) {
      this.getHistory().add(oldLocation, {message: `Save on focus lost [${oldLocation.command}]`})
      return
    }

    // Move within same buffer.
    const newPoint = editor.getCursorBufferPosition()
    const {row, column} = oldPoint.isGreaterThan(newPoint)
      ? oldPoint.traversalFrom(newPoint)
      : newPoint.traversalFrom(oldPoint)

    if (row > this.rowDeltaToRemember || (row === 0 && column > this.columnDeltaToRemember)) {
      this.getHistory().add(oldLocation, {message: `Cursor moved [${oldLocation.command}]`})
    }
  }
}
