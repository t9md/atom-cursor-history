fs = require 'fs'
_  = require 'underscore-plus'

debug = (msg) ->
  return unless atom.config.get('cursor-history.debug')
  console.log msg

module.exports =
class History
  constructor: (max) -> @initialize max
  clear: -> @initialize @max

  initialize: (max) ->
    @index   = 0
    @entries = []
    @max     = max

  isOldest: -> @isEmpty() or @index is 0
  isNewest: -> @isEmpty() or @index >= @entries.length - 1
  isEmpty:  -> @entries.length is 0

  get: (index) -> @entries[index]
  getCurrent:  -> @get @index
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
    @getValid 'next'

  prev: ->
    if @isOldest()
      @dump "Oldest"
      return
    @getValid 'prev'

  removeCurrent: -> @remove(@index)?[0]

  remove: (index, count=1) ->
    removedMarkers = @entries.splice(index, count)

    # Since we can't simply use Maker::copy(), we copy marker shallowly.
    # Only if no copy exists in remaining @entries, we can destroy() it.
    for removedMarker in removedMarkers
      if _.detect(@entries, (marker) -> removedMarker.isEqual(marker))
        continue
      debug "  Destroy: #{@inspectMarker(removedMarker)}"
      removedMarker.destroy()
    removedMarkers

  # History concatenation mimicking Vim's way.
  # newMarker(=old position from where you jump to here) is
  # always added to end of @entries.
  # And delete marker wich have same row of same file with newMarker.
  # e.g || indicate @index
  #  * case-1: Jump from row=7 to row=9 then back with `prev`.
  #   1. newMarker's row=7
  #       => [1,3,5,|7|,8]
  #   2. old 7 is deleted and @index adjusted to point head.
  #       => [1,3,5,8,7,||]
  #   3. `prev` from 9 to 7, add 9 to end, @index not adjusted.
  #       => [1,3,5,8,|7|,9]
  #
  #  * case-2: jump from row=3 to row=7 then back with `prev`.
  #   1. newMarker's row=3
  #       => [1,|3|,5,7,8]
  #   2. 3 added to end and old 3 is deleted, @index adjusted to point to head.
  #       => [1,5,7,8,3,||]
  #   3. `prev` from 7 to 3, add 7 to end, @index not adjusted. old 7 reoved.
  #       => [1,5,8,|3|,7]
  add: (newMarker, pointToHead=true) ->
    # Don't keep marker of same row in one file(URI), so that you will get back to
    # old position(row) only once.
    # See. http://vimhelp.appspot.com/motion.txt.html#jump-motions
    newRow = newMarker.getStartBufferPosition().row
    newURI = newMarker.getProperties().URI
    for marker, i in @entries
      # console.log marker
      URI = marker.getProperties().URI
      row = marker.getStartBufferPosition().row
      if newURI is URI and newRow is row
        marker.destroy()
        if (not pointToHead) and (i <= @index)
          # adjust @index for deletion.
          @index -= 1

    @entries = _.reject @entries, (marker) -> marker.isDestroyed()
    @entries.push newMarker

    if @entries.length > @max
      @remove 0, (@entries.length - @max)

    if pointToHead
      @index = @entries.length
      msg = "Append"
    else
      msg = "Push to Head"
    @dump msg

  pushToHead: (marker) ->
    @add marker, false

  inspectMarker: (marker) ->
    "#{marker.getStartBufferPosition().toString()}, #{marker.getProperties().URI}"

  dump: (msg, force=false) ->
    unless force or atom.config.get('cursor-history.debug')
      return

    console.log "# cursor-history: #{msg}" if msg
    currentValue = if @getCurrent() then @inspectMarker(@getCurrent()) else @getCurrent()
    entries = @entries.map(
      ((e, i) ->
        if i is @index
          "> #{i}: #{@inspectMarker(e)}"
        else
          "  #{i}: #{@inspectMarker(e)}"), @)
    entries.push "> #{@index}:" unless currentValue

    console.log entries.join("\n"), "\n\n"
