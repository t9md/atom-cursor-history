let History

const {CompositeDisposable, Disposable} = require('atom')
const DEFAULT_IGNORE_COMMANDS = [
  'cursor-history:next',
  'cursor-history:prev',
  'cursor-history:next-within-editor',
  'cursor-history:prev-within-editor',
  'cursor-history:clear'
]

function getClosestEditorForTarget (target) {
  if (target && target.closest('atom-text-editor')) {
    return target.closest('atom-text-editor').getModel()
  }
}

class Location {
  constructor (editor, command) {
    this.command = command
    this.editor = editor
    this.point = editor.getCursorBufferPosition()
    this.URI = editor.getURI()
    this.reason = null
  }

  computeNeedToSave (editor, options) {
    if (this.isFocusLost(editor)) {
      this.reason = 'focus lost'
    } else if (this.isMovedEnough(editor, options)) {
      this.reason = 'moved enough'
    }
    return this.reason != null
  }

  isFocusLost (editor) {
    return this.URI ? this.URI !== editor.getURI() : this.editor !== editor
  }

  isMovedEnough (editor, options) {
    const traversal = editor.getCursorBufferPosition().traversalFrom(this.point)
    if (traversal.row === 0) {
      return Math.abs(traversal.column) > options.columnDelta
    } else {
      return Math.abs(traversal.row) > options.rowDelta
    }
  }
}

module.exports = {
  serialize () {
    return {
      history: this.history ? this.history.serialize() : this.state.history
    }
  },

  activate (state) {
    this.state = state
    this.trackedLocation = null // expose to make test easy
    this.mouseCheckTimeout = null
    this.ignoreCommands = new Set([
      'cursor-history:next',
      'cursor-history:prev',
      'cursor-history:next-within-editor',
      'cursor-history:prev-within-editor',
      'cursor-history:clear'
    ])

    const jump = (...args) => this.getHistory().jump(...args)
    this.subscriptions = new CompositeDisposable(
      atom.commands.add('atom-text-editor:not([mini])', {
        'cursor-history:next' () { jump(this.getModel(), 'next') }, // prettier-ignore
        'cursor-history:prev' () { jump(this.getModel(), 'prev') }, // prettier-ignore
        'cursor-history:next-within-editor' () { jump(this.getModel(), 'next', this.getModel()) }, // prettier-ignore
        'cursor-history:prev-within-editor' () { jump(this.getModel(), 'prev', this.getModel()) }, // prettier-ignore
        'cursor-history:dump-history': () => this.getHistory().log('DUMP'),
        'cursor-history:clear': () => this.history && this.history.clear(),
        'cursor-history:toggle-debug': () => this.toggleDebug()
      }),
      atom.config.observe('cursor-history.ignoreCommands', value => this.setIgnoreCommands(value)),
      atom.config.observe('cursor-history.rowDeltaToRemember', value => (this.rowDeltaToRemember = value)),
      atom.config.observe('cursor-history.columnDeltaToRemember', value => (this.columnDeltaToRemember = value))
    )

    this.observeMouse()
    this.observeCommands()
  },

  deactivate () {
    clearTimeout(this.mouseCheckTimeout)
    this.subscriptions.dispose()
    if (this.history) this.history.destroy()
    this.subscriptions = this.history = this.mouseCheckTimeout = null
  },

  setIgnoreCommands (commands) {
    this.ignoreCommands = new Set(DEFAULT_IGNORE_COMMANDS.concat(commands))
  },

  toggleDebug () {
    const newValue = !atom.config.get('cursor-history.debug')
    atom.config.set('cursor-history.debug', newValue)
    console.log('debug: ', newValue)
  },

  getHistory () {
    if (!this.history) {
      if (!History) History = require('./history')
      this.history = History.create(this.state)
    }
    return this.history
  },

  // When mouse clicked, cursor position is updated by atom core using setCursorScreenPosition()
  // To track cursor position change caused by mouse click, I use mousedown event.
  //  - Event capture phase: Cursor position is not yet changed.
  //  - Event bubbling phase: Cursor position updated to clicked position.
  observeMouse () {
    let location, trackingEditor

    const handleCapture = event => {
      clearTimeout(this.mouseCheckTimeout)
      trackingEditor = getClosestEditorForTarget(event.target)
      if (trackingEditor) {
        // When mousedown event was not bubbled by explicitly suppressed by hyperclick,
        // We compare location after 300ms.
        // To avoid duplicate location check, this task is cancelled when mousedown was normally bubled.
        location = new Location(trackingEditor, 'mousedown')
        this.mouseCheckTimeout = this.checkLocationChange(location, 300)
      }
    }

    const handleBubble = event => {
      clearTimeout(this.mouseCheckTimeout)
      if (trackingEditor && trackingEditor === getClosestEditorForTarget(event.target)) {
        if (location) {
          this.checkLocationChange(location, 100)
          location = null
        }
      }
    }

    const element = atom.workspace.getElement()
    element.addEventListener('mousedown', handleCapture, true)
    element.addEventListener('mousedown', handleBubble, false)
    this.subscriptions.add(
      new Disposable(() => {
        element.removeEventListener('mousedown', handleCapture, true)
        element.removeEventListener('mousedown', handleBubble, false)
      })
    )
  },

  observeCommands () {
    const isInterestingCommand = type => type.includes(':') && !this.ignoreCommands.has(type)
    let trackThrottled, trackingEditor
    this.subscriptions.add(
      atom.commands.onWillDispatch(({type, target}) => {
        if (isInterestingCommand(type) && (trackingEditor = getClosestEditorForTarget(target))) {
          if (!trackThrottled) {
            this.trackedLocation = new Location(trackingEditor, type)
          }
          clearTimeout(trackThrottled)
          trackThrottled = setTimeout(() => (trackThrottled = null), 100)
        }
      }),
      atom.commands.onDidDispatch(({type, target}) => {
        const location = this.trackedLocation
        this.trackedLocation = null
        if (location && isInterestingCommand(type) && trackingEditor === getClosestEditorForTarget(target)) {
          // To wait cursor position is set on final destination.
          this.checkLocationChange(location, 100)
        }
      })
    )
  },

  checkLocationChange (location, timeout) {
    if (!location) {
      throw new Error('empty location now allowed for checkLocationChange()')
    }

    return setTimeout(() => {
      const editor = atom.workspace.getActiveTextEditor()
      const options = {
        rowDelta: this.rowDeltaToRemember,
        columnDelta: this.columnDeltaToRemember
      }
      if (editor && location.computeNeedToSave(editor, options)) {
        this.getHistory().add(location)
      }
    }, timeout)
  }
}
