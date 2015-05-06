module.exports =
class History
  constructor: (max) ->
    @initialize(max)

  clear: -> @initialize(@max)

  initialize: (max) ->
    @index   = -1
    @entries = []
    @max     = max

  isNewest: ->
    @entries.length is 0 or @index is @entries.length

  isOldest: ->
    @entries.length is 0 or @index is -1

  isEmpty: ->
    @entries.length is 0

  next: ->
    if @isNewest()
      console.log "newest"
      return
    @index = @index + 1
    @get(@index)

  prev: ->
    if @isOldest()
      console.log "oldest"
      return
    entry = @get(@index)
    @index = @index - 1
    entry

  get: (index) ->
    # console.log index
    @entries[index]

  getLastURI: ->
    @get(@index)?.URI

  add: (entry) ->
    return if @index + 1 is @max
    @index = @index + 1
    @entries[@index] = entry

  setToHead: (entry) ->
    @entries[@entries.length] = entry
    @dump()

    # newLength = @index + 1
    # return if newLength >= @entries.length
    #
    # entries = @entries.splice(newLength, @entries.length - newLength)
    # for {marker} in entries
    #   marker.destroy()

  dump: ->
    # entries = ({URI: e.URI, Point: e.marker.getStartBufferPosition().toString()} for e in @entries)
    entries = (e.marker.getStartBufferPosition().toString() for e in @entries)
    console.log [ entries, @index, @entries.length ]

  serialize: () ->
