fs = require 'fs'
_  = require 'underscore-plus'

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

  isOldest: -> @isEmpty() or @index is 0
  isNewest: -> @isEmpty() or @index >= @entries.length - 1
  isEmpty:  -> @entries.length is 0

  get: (index) -> @entries[index]
  getCurrent:  -> @get(@index)
  getURI: (index) -> @get(index)?.getProperties().URI

  destroy: ->
  serialize: () ->

  getValid: (direction) ->
    until @isEmpty()
      if direction is 'next'
        break if @isNewest()
        @index += 1
      else if direction is 'prev'
        break if @isOldest()
        @index -= 1

      marker = @getCurrent()
      URI = marker.getProperties().URI

      if fs.existsSync URI
        @dump direction
        return marker

      debug "URI not exist: #{URI}"
      @removeCurrent()
      if direction is 'next'
        @index -= 1

    @dump direction

  next: ->
    if @isNewest()
      @dump "Newest"
      return
    @getValid('next')

  prev: ->
    if @isOldest()
      @dump "Oldest"
      return
    @getValid('prev')


  removeCurrent: -> @remove(@index)?[0]
  remove: (index, count=1) ->
    removedMarkers = @entries.splice(index, count)

    # Since we can't simply use Maker::copy(), marker is shallow copied.
    # Only if no copy exists in remaining @entries, we can destroy() it.
    for removedMarker in removedMarkers
      if _.detect(@entries, (marker) -> removedMarker.isEqual(marker))
        continue
      debug "  Destroy: #{@inspectMarker(removedMarker)}"
      removedMarker.destroy()
    removedMarkers

  add: (marker) ->
    msg = []
    unless @isNewest()
      # History concatenation mimicking Vim's way.
      # e.g. Jump from point 3(@index=2) to new 6.
      #   || indicate current @index.
      #   Before: [1,2,|3|,4,5]
      #   After:  [1,2,4,5,4,3,6,||]
      # Steps
      #  0.  start @index=2: [1,2,|3|,4,5]
      #  1.  slice(@index) : @entries = [1,2,|3|,4,5], tail = [3,4,5]
      #  2.  pop()         : @entries = [1,2,|3|,4]
      #  3.  concat:       : [1,2,|3|,4] + [5,4,3] NOTE: tail reversed()
      #  4.  removeCurrent : [1,2,|4|,5,4,3] NOTE: point 3 removed
      #  5.  push new      : [1,2,|4|,5,4,3,6]
      #  6.  @index = @entries.length: [1,2,4,5,4,3,6,||]

      # [FIXME] https://github.com/t9md/atom-cursor-history/issues/2
      # Why I use Array::slice() rather than simply use marker::copy()
      #
      # Marker::copy() call DisplayBuffer.screenPositionForBufferPosition().
      # Marker::copy() throw Error if TextEditor is already destroyed.
      tail = @entries.slice(@index)

      # Since, orignal last entry(5 in above e.g.) is always
      #  included in new @entries after concatenation.
      # We don't need call Marker::destroy().
      # So, we don't need @remove(), simply pop() it.
      @entries.pop()
      @entries = @entries.concat tail.reverse()

      # This deletion is depends on preference, make it configurable?
      # [NOTE] Order is matter, since marker is shallow copied, and when remove(),
      # it check whether it have reference in @entries.
      # So removing should be after all concatenation was done.
      @removeCurrent()

      msg.push "Concatenated"

    oldMark = @entries[@entries.length-1]
    unless marker.isEqual(oldMark)
      msg.push "Save"
      @entries.push marker
    else
      msg.push "Skip"

    if @entries.length > @max
      @remove(0, @entries.length - @max)

    @index = @entries.length
    @dump(msg.join())

  pushToHead: (marker) ->
    @entries.push marker
    @dump "Save Head"

  inspectMarker: (marker) ->
    "#{marker.getStartBufferPosition().toString()}, #{marker.getProperties().URI}"

  dump: (msg, force=false) ->
    unless force or atom.config.get('cursor-history.debug')
      return

    console.log "# cursor-history: #{msg}" if msg
    currentValue = if @getCurrent() then @inspectMarker(@getCurrent()) else @getCurrent()
    # console.log "Index: #{@index}, #{currentValue}"
    entries = @entries.map(
      ((e, i) ->
        if i is @index
          "> #{i}: #{@inspectMarker(e)}"
        else
          "  #{i}: #{@inspectMarker(e)}"), @)
    entries.push "> #{@index}:" unless currentValue

    console.log entries.join("\n"), "\n\n"
