{CompositeDisposable} = require 'atom'
CursorHistory = require './history'

module.exports =
  history: null
  direction: null
  subscriptions: null

  config:
    max:
      type: 'integer'
      default: 100
      minimum: 1
      description: "number of history to remember"
    rowDeltaToRemember:
      type: 'integer'
      default: 4
      minimum: 1
      description: "Only if dirrerence of cursor row exceed this value, cursor position is saved to history"
    debug:
      type: 'boolean'
      default: false
      description: "Output history on console.log"

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @history = new CursorHistory(atom.config.get('cursor-history.max'))
    @history.debug = @debug = atom.config.get('cursor-history.debug')

    @rowDeltaToRemember = atom.config.get('cursor-history.rowDeltaToRemember')
    @subscriptions.add atom.config.onDidChange 'cursor-history.rowDeltaToRemember', ({newValue}) =>
      @rowDeltaToRemember = newValue

    @subscriptions.add atom.config.onDidChange 'cursor-history.debug', ({newValue}) =>
      @debug = @history.debug = newValue

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @next()
      'cursor-history:prev':  => @prev()
      'cursor-history:clear': => @clear()
      'cursor-history:dump':  => @dump()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @subscriptions.add editor.onDidChangeCursorPosition @handleCursorMoved.bind(@)

  dump: -> console.log @history.dump()

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()

  serialize: ->
    @history?.serialize()

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    if @direction is 'prev' and (@history.index + 1 is @history.entries.length)
      marker = cursor.editor.markBufferPosition(oldBufferPosition, {invalidate: 'never', persistent: false})
      @history.pushToHead {marker: marker, URI: cursor.editor.getURI()}
      console.log "Remember Head" if @debug
      @direction = null
      return

    if @direction is 'next' or @direction is 'prev'
      @direction = null
      return

    return if cursor.editor.hasMultipleCursors()
    return unless @needRemember.bind(@)(oldBufferPosition, newBufferPosition, cursor)
    console.log "Remember" if @debug

    marker = cursor.editor.markBufferPosition(oldBufferPosition, {invalidate: 'never', persistent: false})
    @history.add {marker: marker, URI: cursor.editor.getURI()}
    @history.dump() if @debug

  needRemember: (oldBufferPosition, newBufferPosition, cursor) ->
    URI = cursor.editor.getURI()
    unless URI
      # [FIXME] currently buffer without URI is simply ignored.
      # is there any way to support 'untitled' buffer?
      return false

    lastURI = @history.getLastURI()
    if lastURI and lastURI isnt URI
      # Should remember, if buffer path is defferent.
      return true


    if Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember
      return true
    return false

  next: -> @jump('next')
  prev: -> @jump('prev')
  clear: -> @history.clear()

  jump: (direction) ->
    entry = @history[direction]()
    return unless entry

    activeEditor = atom.workspace.getActiveTextEditor()
    return unless activeEditor

    @direction = direction
    {URI, marker} = entry
    pos = marker.getStartBufferPosition()
    if activeEditor.getURI() is URI
      activeEditor.setCursorBufferPosition pos
      return

    atom.workspace.open(URI, searchAllPanes: true).done (editor) =>
      editor.setCursorBufferPosition pos
