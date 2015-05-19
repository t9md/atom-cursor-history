_     = require 'underscore-plus'
Entry = require './entry'

debug = (msg) ->
  return unless atom.config.get('cursor-history.debug')
  console.log msg

module.exports =
class History
  constructor: (max) ->
    @initialize max

  initialize: (max) ->
    @index   = 0
    @entries = []
    @max     = max

  clear: ->
    for entry in @entries
      entry.destroy()
    @initialize @max

  isOldest: -> @isEmpty() or @index is 0
  isNewest: -> @isEmpty() or @index >= @entries.length - 1
  isEmpty:  -> @entries.length is 0

  get: (index) -> @entries[index]
  getCurrent:  -> @get @index
  # getURI: (index) -> @get(index)?.getProperties().URI

  destroy: -> @clear()

  serialize: () ->

  getValid: (direction) ->
    until @isEmpty()
      if direction is 'next'
        break if @isNewest()
        @index += 1
      else if direction is 'prev'
        break if @isOldest()
        @index -= 1

      entry = @getCurrent()

      if entry.isValid()
        return entry

      debug "URI not exist: #{entry.URI}"
      @removeCurrent()
      if direction is 'next'
        @index -= 1

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

  rename: (oldURI, newURI) ->
    for entry in @entries when entry.URI is oldURI
      entry.URI = newURI

  remove: (index, count=1) ->
    entries = @entries.splice(index, count)
    for entry in entries
      debug "  Destroy: #{entry.inspect()}"
      entry.destroy()
    entries

  # rename: (oldURI, , point, URI) ->
  #   @add editor, point, URI, false
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
  add: (editor, point, URI, pointIndexToHead=true) ->
    newEntry = new Entry(editor, point, URI)

    for entry, i in @entries
      if entry.isSameRow newEntry
        entry.destroy()
        # adjust @index for deletion.
        @index -= 1 if i <= @index

    @entries = _.reject @entries, (entry) -> entry.isDestroyed()
    @entries.push newEntry

    if @entries.length > @max
      @remove 0, (@entries.length - @max)

    if pointIndexToHead
      @index = @entries.length

  pushToHead: (editor, point, URI) ->
    @add editor, point, URI, false

  dump: (msg, force=false) ->
    unless force or atom.config.get('cursor-history.debug')
      return
    console.log "# cursor-history: #{msg}" if msg
    entries = @entries.map(
      ((e, i) =>
        if i is @index
          "> #{i}: #{e.inspect()}"
        else
          "  #{i}: #{e.inspect()}"), @)
    entries.push "> #{@index}:" unless @getCurrent()
    console.log entries.join("\n"), "\n\n"
