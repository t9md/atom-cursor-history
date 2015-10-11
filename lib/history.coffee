_ = require 'underscore-plus'
Entry = require './entry'
{debug} = require './utils'

class History
  entries: []
  index: 0

  constructor: (@max) ->
    @init()

  init: ->
    @index = 0
    @entries = []

  isEmpty: ->
    @entries.length is 0

  isNewest: ->
    @isEmpty() or @index >= (@entries.length - 1)

  isValidIndex: (index) ->
    0 <= index <= (@entries.length - 1)

  get: (direction='current', {URI}={}) ->
    if URI?
      current = @get() # save current entry
      while entry = @get(direction)
        return entry if (entry.URI is URI)
      # restore index since not found.
      @index = @entries.indexOf(current)
      return null

    index = switch direction
      when 'next' then @index + 1
      when 'prev' then @index - 1
      else  @index

    return null unless @isValidIndex(index)

    @index = index
    entry = @entries[index]
    if entry.isValid()
      return entry
    else
      debug "URI not exist: #{entry.URI} or Buffer closed"
      _.remove(@entries, entry)
      @index -= 1 if direction is 'next'
      @get(direction)

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
  add: ({editor, point, URI, setIndexToHead}) ->
    setIndexToHead ?= true
    newEntry = new Entry(editor, point, URI)
    for e, i in @entries when e.isAtSameRow(newEntry)
      e.destroy()
      @index -= 1 if i < @index # adjust @index for deletion.
    @entries = _.reject @entries, (e) -> e.isDestroyed()
    @entries.push newEntry

    if @entries.length > @max
      removed = @entries.splice(0, @entries.length - @max)
      e.destroy() for e in removed
    if setIndexToHead
      @index = @entries.length

  clear: ->
    e.destroy() for e in @entries
    @init()

  destroy: ->
    e.destroy() for e in @entries
    {@index, @entries} = {}

  dump: (msg) ->
    ary = []
    for e, i in @entries
      s = if i is @index then "> " else "  "
      ary.push "#{s}#{i}: #{e.inspect()}"
    ary.push "> #{@index}:" if (@index is @entries.length)
    console.log ary.join("\n") + "\n\n"

module.exports = History
