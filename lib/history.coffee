debug = (msg) ->
  return unless atom.config.get('cursor-history.debug')
  console.log msg

module.exports =
class History
  constructor: (max) -> @initialize(max)
  clear: -> @initialize(@max)

  initialize: (max) ->
    @index   = 0
    @entries = []
    @max     = max

  isNewest: -> @isEmpty() or @index is @entries.length - 1
  isOldest: -> @isEmpty() or @index is 0
  isEmpty:  -> @entries.length is 0

  get: (index) -> @entries[index]
  getCurrent:  -> @get(@index)
  getNext:     -> @get(@index + 1)
  getPrev:     -> @get(@index - 1)
  getLastURI:  -> @getPrev()?.URI

  next: ->
    if @isNewest()
      debug "# Newest"
      @dump() if atom.config.get('cursor-history.debug')
      return
    @index += 1
    @dump() if atom.config.get('cursor-history.debug')
    @getCurrent()

  prev: ->
    if @isOldest()
      debug "# Oldest"
      @dump() if atom.config.get('cursor-history.debug')
      return
    @index -= 1
    @dump() if atom.config.get('cursor-history.debug')
    @getCurrent()

  truncate: ->
    newLength = @index + 1
    return if newLength >= @entries.length

    deleteCount = @entries.length - newLength
    debug "# Truncate #{deleteCount}"
    entries = @entries.splice(newLength, deleteCount)
    for {marker} in entries
      marker.destroy()

  add: (entry) ->

    oldPos = @getCurrent()?.marker.getStartBufferPosition()
    newPos = entry.marker.getStartBufferPosition()
    unless newPos.isEqual(oldPos)
      if @entries.length is @max
        @entries.splice(0, 1)
      debug "-- save"
      @entries[@index] = entry
    else
      debug "-- skip"

    @truncate()
    @index = @entries.length

  pushToHead: (entry) ->
    @entries.push entry
    @dump() if atom.config.get('cursor-history.debug')

  inspectEntry: (entry) ->
    "#{entry.marker.getStartBufferPosition().toString()}, #{entry.URI}"

  dump: ->
    currentValue = if @getCurrent() then @inspectEntry(@getCurrent()) else @getCurrent()
    console.log " - index #{@index} #{currentValue}"
    entries = @entries.map(
      ((e, i) ->
        if i is @index
          "> #{i}: #{@inspectEntry(e)}"
        else
          "  #{i}: #{@inspectEntry(e)}"), @)
    entries.push "> #{@index}:" unless currentValue

    console.log entries.join("\n")

  serialize: () ->
