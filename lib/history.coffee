_ = require 'underscore-plus'
Entry = require './entry'
settings = require './settings'

class History
  constructor: ->
    @init()

  init: ->
    @index = 0
    @entries = []

  clear: ->
    e.destroy() for e in @entries
    @init()

  destroy: ->
    e.destroy() for e in @entries
    {@index, @entries} = {}

  isIndexAtHead: ->
    @index is @entries.length

  findIndex: (direction, URI=null) ->
    [start, indexes] = switch direction
      when 'next' then [start=(@index + 1), [start..(@entries.length - 1)]]
      when 'prev' then [start=(@index - 1), [start..0]]

    # Check if valid index range
    return null unless (0 <= start <= (@entries.length - 1))

    for index in indexes
      entry = @entries[index]
      continue unless entry.isValid()
      if URI?
        return index if (entry.URI is URI)
      else
        return index

  get: (direction, {URI}={}) ->
    index = @findIndex(direction, URI)
    if index?
      @entries[@index=index]

  # History concatenation mimicking Vim's way.
  # newEntry(=old position from where you jump to land here) is
  # *always* added to end of @entries.
  # Whenever newEntry is added old Marker wich have same row with
  # newEntry is removed.
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
  # 2. Jump from row=7 to row=9, newEntry(row=7) is appended to end
  #    of @entries then old row=7(@index=3) was deleted.
  #    @index adjusted to head of @entries(@index = @entries.length).
  # 3. Back from row=9 to row=7 with `cursor-history:prev`.
  #    newEntry(row=9) is appended to end of @entries.
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
  # 2. Jump from row=3 to row=7, newEntry(row=3) is appended to end
  #    of @entries then old row=3(@index=1) was deleted.
  #    @index adjusted to head of @entries(@index = @entries.length).
  # 3. Back from row=7 to row=3 with `cursor-history:prev`.
  #    newEntry(row=7) is appended to end of @entries.
  #    No special @index adjustment.
  #
  add: ({editor, point, URI}, {setIndexToHead}={}) ->
    newEntry = new Entry(editor, point, URI)
    e.destroy() for e in @entries when e.isAtSameRow(newEntry)
    @entries.push newEntry

    if setIndexToHead ? true
      # Only when setIndexToHead is true, we can safely remove @entries.
      @removeEntries()
      @index = @entries.length

  removeEntries: ->
    # Scrub invalid
    e.destroy() for e in @entries when not e.isValid()
    @entries = (e for e in @entries when e.isValid())

    # Remove if exceeds max
    removeCount = @entries.length - settings.get('max')
    if removeCount > 0
      removed = @entries.splice(0, removeCount)
      e.destroy() for e in removed

  inspect: (msg) ->
    ary =
      for e, i in @entries
        s = if (i is @index) then "> " else "  "
        "#{s}#{i}: #{e.inspect()}"
    ary.push "> #{@index}:" if (@index is @entries.length)
    ary.join("\n")

module.exports = History
