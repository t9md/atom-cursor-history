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
  # newMarker(=old position from where you jump to land here) is
  # *always* added to end of @entries.
  # Whenever newMarker is added old Marker wich have same row with
  # newMarker is removed.
  # This allows you to get back to old position(row) only once.
  #
  #  http://vimhelp.appspot.com/motion.txt.html#jump-motions
  #
  # e.g
  #  1st column: index of @entries
  #  2nd column: row of each Marker indicate.
  #  >: indicate @index
  #
  # Case-1:
  #   Jump from row=7 to row=9 then back with `cursor-history:prev`.
  #
  #     [1]   [2]    [3]
  #     0 1   0 1    0 1
  #     1 3   1 3    1 3
  #     2 5   2 5    2 5
  #   > 3 7   3 8    3 8
  #     4 8   4 7  > 4 7
  #         >   _    5 9
  #
  # 1. Initial State, @index=3(row=7)
  # 2. Jump from row=7 to row=9, newMarker(row=7) is appended to end
  #    of @entries then old row=7(@index=3) was deleted.
  #    @index adjusted to head of @entries(@index = @entries.length).
  # 3. Back from row=9 to row=7 with `cursor-history:prev`.
  #    newMarker(row=9) is appended to end of @entries.
  #    No special @index adjustment.
  #
  # Case-2:
  #  Jump from row=3 to row=7 then back with `cursor-history.prev`.
  #
  #     [1]   [2]    [3]
  #     0 1   0 1    0 1
  #   > 1 3   1 5    1 5
  #     2 5   2 7    2 8
  #     3 7   3 8  > 3 3
  #     4 8   4 3    4 7
  #         >   _
  #
  # 1. Initial State, @index=1(row=3)
  # 2. Jump from row=3 to row=7, newMarker(row=3) is appended to end
  #    of @entries then old row=3(@index=1) was deleted.
  #    @index adjusted to head of @entries(@index = @entries.length).
  # 3. Back from row=7 to row=3 with `cursor-history:prev`.
  #    newMarker(row=7) is appended to end of @entries.
  #    No special @index adjustment.
  #
  add: (newMarker, pointToHead=true) ->
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
