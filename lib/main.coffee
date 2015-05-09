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
      'cursor-history:toggle-debug': => @toggleDebug()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @subscriptions.add editor.onDidChangeCursorPosition @handleCursorMoved.bind(@)

  dump: ->
    @history.dump('', true)

  toggleDebug: ->
    atom.config.toggle('cursor-history.debug')
    state = atom.config.get('cursor-history.debug') and "enabled" or "disabled"
    console.log "cursor-history: debug #{state}"

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()

  serialize: ->
    @history?.serialize()

  createMarker: (cursor, point, properties) ->
    marker = cursor.editor.markBufferPosition point, {invalidate: 'never', persistent: false}
    marker.setProperties properties
    marker

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    return if cursor.editor.hasMultipleCursors()

    # @debug "Direction: #{@direction}, Index: #{@history.index}"
    if @direction is 'prev' and @history.isNewest()
      @history.pushToHead @createMarker(cursor, oldBufferPosition, URI: cursor.editor.getURI())

    if @direction
      @direction = null
      return

    return unless @needRemember.bind(@)(oldBufferPosition, newBufferPosition, cursor)
    @history.add @createMarker(cursor, oldBufferPosition, URI: cursor.editor.getURI())

  needRemember: (oldBufferPosition, newBufferPosition, cursor) ->
    URI = cursor.editor.getURI()

    # [FIXME] currently buffer without URI is simply ignored.
    # is there any way to support 'untitled' buffer?
    return false unless URI

    lastURI = @history.getURI(@history.index - 1)
    if lastURI and lastURI isnt URI
      # Should remember, if buffer path is defferent.
      return true

    if Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember
      return true
    return false

  next:  -> @jump('next')
  prev:  -> @jump('prev')
  clear: -> @history.clear()

  jump: (direction) ->
    # TextEditor workspace like Settings tab don't have editor.
    activeEditor = atom.workspace.getActiveTextEditor()
    return unless activeEditor

    marker = @history[direction]()
    return unless marker

    @direction = direction

    URI = marker.getProperties().URI
    pos = marker.getStartBufferPosition()

    if activeEditor.getURI() is URI
      # Within active editor.
      activeEditor.setCursorBufferPosition pos
      return

    atom.workspace.open(URI, searchAllPanes: true).done (editor) =>
      editor.setCursorBufferPosition pos
