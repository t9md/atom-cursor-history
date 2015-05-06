{CompositeDisposable, Point} = require 'atom'
CursorHistory = require './cursor-history'

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

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @history = new CursorHistory

    atom.commands.add 'atom-workspace',
      'cursor-history:next': => @next()
      'cursor-history:prev': => @prev()
      'cursor-history:add':  => @add()
      'cursor-history:reset':  => @reset()
      'cursor-history:dump':  => @dump()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @subscriptions.add editor.onDidChangeCursorPosition @handleCursorMoved.bind(@)

  dump: -> @history.dump()

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()

  serialize: ->
    @history?.serialize()

  handleCursorMoved: (event) ->
    # console.log cursor
    if @direction is 'next' or @direction is 'prev'
      @direction = null
      return

    return unless @needRemember(event)
    # console.log "Remember"
    @history.add
      point: event.newBufferPosition
      URI: event.cursor.editor.getURI()

  needRemember: ({oldBufferPosition, newBufferPosition, cursor}) ->
    if cursor.editor.hasMultipleCursors()
      return false
    if Math.abs(oldBufferPosition.row - newBufferPosition.row) >= 4
      return true
    return false

  jump: (@direction) ->
    entry = @history[@direction]()
    return unless entry
    {URI, point} = entry

    atom.workspace.open(URI, split: 'right', searchAllPanes: true).done (editor) =>
      editor.setCursorBufferPosition point

  next: -> @jump('next')
  prev: -> @jump('prev')
  reset: -> @history.reset()
