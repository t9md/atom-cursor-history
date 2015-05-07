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

  debug: (msg) ->
    return unless atom.config.get('cursor-history.debug')
    console.log msg

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @history = new CursorHistory(atom.config.get('cursor-history.max'))

    @rowDeltaToRemember = atom.config.get('cursor-history.rowDeltaToRemember')
    @subscriptions.add atom.config.onDidChange 'cursor-history.rowDeltaToRemember', ({newValue}) =>
      @rowDeltaToRemember = newValue

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @next()
      'cursor-history:prev':  => @prev()
      'cursor-history:clear': => @clear()
      'cursor-history:dump':  => @dump()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @subscriptions.add editor.onDidChangeCursorPosition @handleCursorMoved.bind(@)

  dump: ->
    @history.dump()

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()

  serialize: ->
    @history?.serialize()

  creatMarker: (cursor, point, properties) ->
    marker = cursor.editor.markBufferPosition point, {invalidate: 'never', persistent: false}
    marker.setProperties properties
    marker



  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    return if cursor.editor.hasMultipleCursors()

    @debug "Direction: #{@direction}, Index: #{@history.index}"
    if @direction is 'prev' and not @history.getNext()
      @debug "# Remember Head"
      @history.pushToHead @creatMarker(cursor, oldBufferPosition, URI: cursor.editor.getURI())
      @direction = null
      return

    if @direction is 'next' or @direction is 'prev'
      @direction = null
      return

    return unless @needRemember.bind(@)(oldBufferPosition, newBufferPosition, cursor)
    @debug "# Need to remember"
    @history.add @creatMarker(cursor, oldBufferPosition, URI: cursor.editor.getURI())
    @history.dump() if atom.config.get('cursor-history.debug')

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
    activeEditor = atom.workspace.getActiveTextEditor()
    return unless activeEditor

    marker = @history[direction]()
    return unless marker

    URI = marker.getProperties().URI

    @direction = direction
    pos = marker.getStartBufferPosition()
    if activeEditor.getURI() is URI
      activeEditor.setCursorBufferPosition pos
      return

    atom.workspace.open(URI, searchAllPanes: true).done (editor) =>
      editor.setCursorBufferPosition pos
