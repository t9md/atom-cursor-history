{CompositeDisposable, TextEditor, Emitter} = require 'atom'
path = require 'path'

History    = require './history'
LastEditor = require './last-editor'

Config =
  max:
    type: 'integer'
    default: 100
    minimum: 1
    description: "number of history to remember"
  rowDeltaToRemember:
    type: 'integer'
    default: 4
    minimum: 0
    description: "Only if dirrerence of cursor row exceed this value, cursor position is saved to history"
  debug:
    type: 'boolean'
    default: false
    description: "Output history on console.log"
  keepPane:
    type: 'boolean'
    default: false
    description: "Open history entry always on same pane."
  flashOnJump:
    type: 'boolean'
    default: false
    description: "flash line on jump to history point"
  flashDurationMilliSeconds:
    type: 'integer'
    default: 200
    description: "Duration for flash"
  flashColor:
    type: 'string'
    default: 'info'
    enum: ['info', 'success', 'warning', 'error', 'highlight', 'selected']
    description: 'flash color style, correspoinding to @background-color-#{flashColor}: see `styleguide:show`'

module.exports =
  config: Config
  history: null
  subscriptions: null
  lastEditor: null
  locked: false

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @emitter       = new Emitter
    @history       = new History atom.config.get('cursor-history.max')

    @rowDeltaToRemember = atom.config.get 'cursor-history.rowDeltaToRemember'
    @subscriptions.add atom.config.onDidChange 'cursor-history.rowDeltaToRemember', ({newValue}) =>
      @rowDeltaToRemember = newValue

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @next()
      'cursor-history:prev':  => @prev()
      'cursor-history:clear': => @clear()
      'cursor-history:dump':  => @dump()
      'cursor-history:toggle-debug': => @toggleDebug()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @handleChangePath(editor)
      # orgURI = editor.getURI()

      @subscriptions.add editor.onDidChangeCursorPosition @handleCursorMoved.bind(@)

    @subscriptions.add atom.workspace.observeActivePaneItem (item) =>
      if item instanceof TextEditor and item.getURI()
        @handlePaneItemChanged item

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item}) =>
      if item instanceof TextEditor and item.getURI()
        LastEditor.saveDestroyedEditor item

    @subscriptions.add @onWillJumpToHistory (direction) =>
      @lock()

    @subscriptions.add @onDidJumpToHistory (direction) =>
      @unLock()
      @highlightCursorLine() if atom.config.get('cursor-history.flashOnJump')
      @history.dump direction

  highlightCursorLine: ->
    activeEditor = @getActiveTextEditor()
    range = activeEditor.getSelectedBufferRange()
    marker = activeEditor.markBufferRange range,
      invalidate: 'never'
      persistent: false

    color = atom.config.get('cursor-history.flashColor')
    decoration = activeEditor.decorateMarker marker,
      type: 'line'
      class: "cursor-history-#{color}"

    setTimeout  ->
      decoration.getMarker().destroy()
    , atom.config.get('cursor-history.flashDurationMilliSeconds')

  onWillJumpToHistory: (callback) ->
    @emitter.on 'will-jump-to-history', callback

  onDidJumpToHistory: (callback) ->
    @emitter.on 'did-jump-to-history', callback

  handleChangePath: (editor) ->
    orgURI = editor.getURI()

    @subscriptions.add editor.onDidChangePath =>
      newURI = editor.getURI()
      @history.rename orgURI, newURI
      @lastEditor.rename orgURI, newURI
      orgURI = newURI


  handlePaneItemChanged: (item) ->
    # We need to track former active pane to know cursor position when active pane was changed.
    @lastEditor ?= new LastEditor(item)
    {editor, point, URI: lastURI} = @lastEditor.getInfo()

    if @isLocked()
      @debug "locked! ignore pane Change"

    else if lastURI isnt item.getURI()
      @history.add editor, point, lastURI
      @history.dump "[Pane item changed] save history"

    @lastEditor.set item

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    if @isLocked()
      @debug "locked! ignore cursor Move"
      return

    editor = cursor.editor
    return if editor.hasMultipleCursors()
    return unless URI = editor.getURI()

    if @needRemember(oldBufferPosition, newBufferPosition, cursor)
      @history.add editor, oldBufferPosition, URI
      @history.dump "[Cursor moved] save history"

  needRemember: (oldBufferPosition, newBufferPosition, cursor) ->
    # Line number delata exceeds or not.
    if Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember
      return true
    else
      return false

  lock:     -> @locked = true
  unLock:   -> @locked = false
  isLocked: -> @locked

  clear: ->
    @history.clear()

  next:  -> @jump 'next'
  prev:  -> @jump 'prev'

  jump: (direction) ->
    # Settings tab is not TextEditor instance.
    return unless activeEditor = @getActiveTextEditor()
    return unless entry = @history[direction]()

    if direction is 'prev' and @history.isNewest()
      point = activeEditor.getCursorBufferPosition()
      URI   = activeEditor.getURI()
      # console.log "Push to Head"
      @history.pushToHead activeEditor, point, URI

    @emitter.emit 'will-jump-to-history'

    {URI, point} = entry.getInfo()

    if activeEditor.getURI() is URI
      # Jump within same pane
      activeEditor.setCursorBufferPosition point
      @emitter.emit 'did-jump-to-history', direction

    else
      # Jump to different pane
      options =
        initialLine: point.row
        initialColumn: point.column
        searchAllPanes: !atom.config.get('cursor-history.keepPane')

      atom.workspace.open(URI, options).done (editor) =>
        @emitter.emit 'did-jump-to-history', direction

    @history.dump direction

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()
    @history = null

  serialize: ->
    @history?.serialize()

  debug: (msg) ->
    return unless atom.config.get 'cursor-history.debug'
    console.log msg

  inspectEditor: (editor) ->
    "#{editor.getCursorBufferPosition()} #{path.basename(editor.getURI())}"

  getActiveTextEditor: ->
    atom.workspace.getActiveTextEditor()

  dump: ->
    @history.dump '', true

  toggleDebug: ->
    atom.config.toggle 'cursor-history.debug'
    state = atom.config.get('cursor-history.debug') and "enabled" or "disabled"
    console.log "cursor-history: debug #{state}"
