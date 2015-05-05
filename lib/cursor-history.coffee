module.exports =
class CursorHistory
  constructor: () ->
    @index   = -1
    @history = []
    @max     = atom.config.get('cursor-history.max')

  next: ->
    if @index is @history.length - 1
      console.log 'newest'
      return
    @get(@index = @index + 1)

  prev: ->
    if @index is 0
      console.log  "oldest"
      return
    @get(@index = @index - 1)

  get: (index) ->
    @history[index]

  # lastReturned: ->
  #   @history[index]

  peek: ->
    @history[@index]

  add: (cursor) ->
    if @index + 1 >= @max
      console.log 'max'
      return
    @index = @index + 1
    @history[@index] = cursor
    @history.length = @index + 1

  dump: ->
    console.log [ @history, @index ]

  serialize: () ->
