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
  # e.g. Jump from point 3(@index=2) to new 6.
  #   || indicate current @index.
  #   Before: [1,2,|3|,4,5]
  #   After:  [1,2,4,5,4,3,6,||]

  # Old position is always inserted to end of @entries.
  #  and remove older entry wich have samel line of new ently
  # [case-1]
  #   Before               : [1,3,5,|7|,8]
  #   jump to line 9       : [1,3,5,8,7,||] NOTE: 7 inserted end, and old removed
  #   back to 7 with `prev`: [1,3,5,8,|7|,9]
  # [case-2]
  #   Before               : [1,|3|,5,7,8]
  #   jumpto line 7        : [1,5,7,8,3,||] NOTE: 3 inserted end
  #   back to 3 with `prev`: [1,5,8,|3|,7] NOTE: 7 inserted end

  # concatenate: (newMarker) ->
  #   # [FIXME] https://github.com/t9md/atom-cursor-history/issues/2
  #   # Why I use Array::slice() rather than simply use marker::copy()
  #   #
  #   # Marker::copy() call DisplayBuffer.screenPositionForBufferPosition().
  #   # Marker::copy() throw Error if TextEditor is already destroyed.
  #   tail = @entries.slice @index
  #
  #   # Since, orignal last entry(5 in above e.g.) is always
  #   #  included in new @entries after concatenation.
  #   # So, no need safely @remove() with destroy(), we can simply pop() it.
  #   @entries.pop()
  #   @entries = @entries.concat tail.reverse()
  #
  #   # We don't keep samel row of same file(URI), so that you will get back to
  #   # old position only once.
  #   # See.
  #   # http://vimhelp.appspot.com/motion.txt.html#jump-motions
  #   newRow = newMarker.getStartBufferPosition().row
  #   newURI = newMarker.getProperties().URI
  #
  #   for marker in @entries
  #     if marker.isEqual(newMarker)
  #       marker.destroy()
  #       continue
  #
  #     URI = marker.getProperties().URI
  #     row = marker.getStartBufferPosition().row
  #     if newURI is URI and newRow is row
  #       marker.destroy()
  #
  #   @entries = _.select (@entries , (marker) -> marker.isValid()

  add: (newMarker, pointToHead=true) ->
    newRow = newMarker.getStartBufferPosition().row
    newURI = newMarker.getProperties().URI

    for marker in @entries
      # if marker.isEqual(newMarker)
      #   marker.destroy()
      #   continue
      URI = marker.getProperties().URI
      row = marker.getStartBufferPosition().row
      if newURI is URI and newRow is row
        marker.destroy()

    @entries = _.reject @entries , (marker) -> marker.isDestroyed()
    @entries.push newMarker

    if @entries.length > @max
      @remove 0, @entries.length - @max

    if pointToHead
      @index = @entries.length
      msg = "Append"
    else
      msg = "Save to Head"
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
