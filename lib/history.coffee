module.exports =
class History
  constructor: (max) -> @initialize(max)
  clear: -> @initialize(@max)

  initialize: (max) ->
    @debug   = false
    @index   = 0
    @entries = []
    @max     = max

  isNewest: -> @index is @entries.length - 1
  isOldest: -> @index is 0

  isEmpty: ->
    @entries.length is 0

  next: ->
    return if @isEmpty()
    if @isNewest()
      if @debug
        console.log "# Newest"
        @dump()
      return
    @index = @index + 1
    if @debug
      @dump()
    @get(@index)

  prev: ->
    return if @isEmpty()
    if @isOldest()
      if @debug
        console.log "# Oldest"
        @dump()
      return
    @index = @index - 1
    @dump() if @debug
    @get(@index)

  get: (index) ->
    @entries[index]

  getLastURI: ->
    @get(@index-1)?.URI

  truncate: ->
    newLength = @index + 1
    return if newLength >= @entries.length
    deleteCount = @entries.length - newLength
    console.log "truncate #{deleteCount}" if @debug
    entries = @entries.splice(newLength, deleteCount)
    for {marker} in entries
      marker.destroy()

  add: (entry) ->
    if @entries.length is @max
      @entries.splice(0, 1)

    @truncate()

    oldPos = @get(@index)?.marker.getStartBufferPosition()
    newPos = entry.marker.getStartBufferPosition()
    unless newPos.isEqual(oldPos)
      console.log "save" if @debug
      @entries.push entry
    else
      console.log "skip" if @debug

    @index = @entries.length

  pushToHead: (entry) ->
    @entries.push entry
    @dump() if @debug

  dump: ->
    entries = ({marker: e.marker.getStartBufferPosition().toString(), URI: e.URI} for e in @entries)
    console.log " - index #{@index}"
    entries = entries.map(
      ((e, i) ->
        if i is @index
          "> #{i}: #{e.marker} #{e.URI}"
        else
          "  #{i}: #{e.marker} #{e.URI}"), @)
    entries.push ">" unless @entries[@index]
    console.log entries.join("\n")

  serialize: () ->
