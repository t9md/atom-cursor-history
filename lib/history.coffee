module.exports =
class History
  constructor: (max) ->
    @initialize(max)

  reset: -> @initialize(@max)

  initialize: (max) ->
    @index   = -1
    @entries = []
    @max     = max

  isNewest: ->
    @entries.length is 0 or @index is @entries.length - 1

  isOldest: ->
    @entries.length is 0 or @index is 0

  next: ->
    if @isNewest()
      # console.log "newest"
      return
    @get(@index + 1)

  prev: ->
    if @isOldest()
      # console.log "oldest"
      return
    @get(@index - 1)

  get: (@index) ->
    @entries[@index]

  add: (entry) ->
    return if @index + 1 is @max
    @index = @index + 1
    @entries[@index] = entry

    newLength = @index + 1
    return if newLength >= @entries.length

    entries = @entries.splice(newLength, @entries.length - newLength)
    for {marker} in entries
      marker.destroy()

  dump: ->
    console.log [ @entries, @index, @entries.length ]

  serialize: () ->
