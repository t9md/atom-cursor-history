{CompositeDisposable, TextEditor, Emitter} = require 'atom'
path = require 'path'

History    = require './history'
LastEditor = require './last-editor'
settings   = require './settings'

module.exports =
  config: settings.config
  history: null
  subscriptions: null
  lastEditor: null
  locked: false

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @emitter       = new Emitter
    @history       = new History settings.max()

    @rowDeltaToRemember = settings.rowDeltaToRemember()
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
      @flashCursorLine() if settings.flashOnJump()
      @history.dump direction

  flashCursorLine: ->
    activeEditor = @getActiveTextEditor()
    range = activeEditor.getSelectedBufferRange()
    marker = activeEditor.markBufferRange range,
      invalidate: 'never'
      persistent: false

    color = settings.flashColor()
    decoration = activeEditor.decorateMarker marker,
      type: 'line'
      class: "cursor-history-#{color}"

    setTimeout  ->
      decoration.getMarker().destroy()
    , settings.flashDurationMilliSeconds()

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
      # Intentionally disable `autoscroll` to set cursor position middle of
      # screen afterward.
      activeEditor.setCursorBufferPosition point, autoscroll: false
      # Adjust cursor position to middle of screen.
      activeEditor.scrollToCursorPosition()
      @emitter.emit 'did-jump-to-history', direction

    else
      # Jump to different pane
      options =
        initialLine: point.row
        initialColumn: point.column
        searchAllPanes: !settings.keepPane()

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
    return unless settings.debug()
    console.log msg

  inspectEditor: (editor) ->
    "#{editor.getCursorBufferPosition()} #{path.basename(editor.getURI())}"

  getActiveTextEditor: ->
    atom.workspace.getActiveTextEditor()

  dump: ->
    @history.dump '', true

  toggleDebug: ->
    settings.debug('toggle')
    # atom.config.toggle 'cursor-history.debug'
    state = settings.debug() and "enabled" or "disabled"
    console.log "cursor-history: debug #{state}"
