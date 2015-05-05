{CompositeDisposable, Point} = require 'atom'
CursorHistory = require './cursor-history'

module.exports =
  history: null
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
      'cursor-history:add': => @add()


    # Essential: Calls your `callback` when a {Cursor} is moved. If there are
    # multiple cursors, your callback will be called for each cursor.
    #
    # * `callback` {Function}
    #   * `event` {Object}
    #     * `oldBufferPosition` {Point}
    #     * `oldScreenPosition` {Point}
    #     * `newBufferPosition` {Point}
    #     * `newScreenPosition` {Point}
    #     * `textChanged` {Boolean}
    #     * `cursor` {Cursor} that triggered the event
    #
    # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @subscriptions.add editor.onDidChangeCursorPosition (event) => @add(event)

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()

  serialize: ->
    @history?.serialize()

  editor: ->
    atom.workspace.getActiveTextEditor()

  getCursor: ->
    @editor().getCursor()

  getCursorPosition: ->
    @getCursor().getBufferPosition()

  setCursorPosition: (pos) ->
    @getCursor().setBufferPosition pos

  add: ({oldBufferPosition, newBufferPosition}) ->
    if Math.abs(oldBufferPosition.row - newBufferPosition.row) < 4
      return
    # if newBufferPosition.isEqual @history.peek()
      # return
    @history.add oldBufferPosition
    console.log @history.dump()

  next: ->
    pos = @history.next()
    @setCursorPosition pos if pos?

  prev: ->
    pos = @history.prev()
    @setCursorPosition pos if pos?
