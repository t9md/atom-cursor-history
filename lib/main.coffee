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

  add: ->
    @history.add @getCursorPosition()
    console.log @history.dump()

  next: ->
    pos = @history.next()
    @setCursorPosition pos if pos?

  prev: ->
    pos = @history.prev()
    @setCursorPosition pos if pos?
