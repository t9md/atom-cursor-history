module.exports =
class CursorHistory
  constructor: (max) ->
    @initialize(max)

  reset: -> @initialize(@max)

  initialize: (max) ->
    @index   = -1
    @entries = []
    @max     = max

  next: ->
    if @index is @entries.length - 1
      # console.log "newest"
      return
    @get(@index + 1)

  prev: ->
    if @index is 0
      # console.log "oldest"
      return
    @get(@index - 1)

  get: (@index) ->
    @entries[@index]

  add: (entry) ->
    return if @index + 1 is @max
    @index = @index + 1
    @entries[@index] = entry
    @entries.length = @index + 1

  dump: ->
    console.log [ @entries, @index, @entries.length ]

  serialize: () ->
