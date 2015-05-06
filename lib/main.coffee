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

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @history = new CursorHistory(atom.config.get('cursor-history.max'))

    @rowDeltaToRemember = atom.config.get('cursor-history.rowDeltaToRemember')
    @subscriptions.add atom.config.observe 'cursor-history.rowDeltaToRemember', (newValue) =>
      @rowDeltaToRemember = newValue

    atom.commands.add 'atom-workspace',
      'cursor-history:next': => @next()
      'cursor-history:prev': => @prev()
      'cursor-history:reset':  => @reset()
      # 'cursor-history:dump':  => @dump()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @subscriptions.add editor.onDidChangeCursorPosition @handleCursorMoved.bind(@)

  # dump: -> console.log @direction

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()

  serialize: ->
    @history?.serialize()

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    if @direction is 'next' or @direction is 'prev'
      @direction = null
      return

    return if cursor.editor.hasMultipleCursors()
    return unless @needRemember.bind(@)(oldBufferPosition, newBufferPosition, cursor)

    # console.log "Remember"

    # [FIXME] currently buffer without URI is simply ignored.
    # is there any way to support 'untitled' buffer?
    URI = cursor.editor.getURI()
    return unless URI

    marker = cursor.editor.markBufferPosition(newBufferPosition, {invalidate: 'never', persistent: false})
    @history.add {marker: marker, URI: URI}

  needRemember: (oldBufferPosition, newBufferPosition, cursor) ->
    # [FIXME] handle active editor change.
    if Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember
      return true
    return false

  next: -> @jump('next')
  prev: -> @jump('prev')
  reset: -> @history.reset()

  jump: (@direction) ->
    entry = @history[@direction]()
    unless entry
      @direction = null
      return
    {URI, marker} = entry
    atom.workspace.open(URI, searchAllPanes: true).done (editor) =>
      editor.setCursorBufferPosition marker.getStartBufferPosition()
