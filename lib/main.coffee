{CompositeDisposable, TextEditor} = require 'atom'
path = require 'path'

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

module.exports =
  history: null
  direction: null
  subscriptions: null
  lastEditor: null
  config: Config
  locked: false

  debug: (msg) ->
    return unless atom.config.get 'cursor-history.debug'
    console.log msg

  activate: (state) ->
    @subscriptions = new CompositeDisposable

    History = require './history'
    @history = new History atom.config.get('cursor-history.max')

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
      @subscriptions.add editor.onDidChangeCursorPosition @handleCursorMoved.bind(@)

    @subscriptions.add atom.workspace.observeActivePaneItem @handlePaneChanged.bind(@)

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item}) =>
      if item instanceof TextEditor and item.getURI()
        LastEditor.saveDestroyedEditor item

  inspectEditor: (editor) ->
    "#{editor.getCursorBufferPosition()} #{path.basename(editor.getURI())}"

  dump: ->
    console.log @lastEditor.getInfo().URI
    # console.log @lastEditor
    @history.dump '', true

  toggleDebug: ->
    atom.config.toggle 'cursor-history.debug'
    state = atom.config.get('cursor-history.debug') and "enabled" or "disabled"
    console.log "cursor-history: debug #{state}"

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()

  serialize: ->
    @history?.serialize()

  handlePaneChanged: (item) ->
    return unless item instanceof TextEditor
    return unless newURI = item.getURI()

    # We need to track former active pane to know cursor position when active pane was changed.
    unless @lastEditor
      @lastEditor = new LastEditor(item)
      return

    {editor, URI, point} = @lastEditor.update()
    # {editor, URI, point} = @lastEditor.getInfo()

    if @isLocked()
      console.log "locked! ignore pane Change"
    else
      if newURI isnt URI
        # We save history only if URI(filePath) is different.
        @history.add editor, point, URI
        @history.dump "[Pane item changed] save history"

    @lastEditor.init item

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    if @isLocked()
      console.log "locked! ignore cursor Move"
      return

    editor = cursor.editor
    return if editor.hasMultipleCursors()
    # # [FIXME] Currently buffer without URI is simply ignored.
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

  getActiveTextEditor: ->
    atom.workspace.getActiveTextEditor()

  lock:     -> @locked = true
  unLock:   -> @locked = false
  isLocked: -> @locked

  clear: -> @history.clear()

  next:  -> @jump 'next'
  prev:  -> @jump 'prev'

  jump: (direction) ->
    # Settings tab is not TextEditor instance.
    return unless activeEditor = @getActiveTextEditor()
    return unless entry = @history[direction]()

    if direction is 'prev' and @history.isNewest()
      point = activeEditor.getCursorBufferPosition()
      URI   = activeEditor.getURI()
      console.log "Push to Head"
      @history.pushToHead activeEditor, point, URI

    @lock()

    {URI, point} = entry.getInfo()
    if activeEditor.getURI() is URI
      # Jump within same pane
      activeEditor.setCursorBufferPosition point
      @unLock()
    else
      # Jump to different pane
      options =
        initialLine: point.row
        initialColumn: point.column
        searchAllPanes: true

      atom.workspace.open(URI, options).done (editor) =>
        # console.log "opend with another pane"
        @unLock()

    @history.dump direction
