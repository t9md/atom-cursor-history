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
    entry.destroy() for entry in @entries
    @init()

  destroy: ->
    entry.destroy() for entry in @entries
    {@index, @entries} = {}

  findValidIndex: (direction, {URI}={}) ->
    lastIndex = @entries.length - 1

    switch direction
      when 'next'
        startIndex = @index + 1
        indexesToSearch = [startIndex..lastIndex]
      when 'prev'
        startIndex = @index - 1
        indexesToSearch = [startIndex..0]

    return unless 0 <= startIndex <= lastIndex

    for index in indexesToSearch when (entry = @entries[index]).isValid()
      if URI?
        return index if entry.URI is URI
      else
        return index
    null

  get: (direction, options={}) ->
    index = @findValidIndex(direction, options)
    if index?
      @entries[@index=index]

  isIndexAtHead: ->
    @index is @entries.length

  setIndexToHead: ->
    @index = @entries.length

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
  add: (location, {setIndexToHead}={}) ->
    {editor, point, URI} = location
    newEntry = new Entry(editor, point, URI)

    if settings.get('keepSingleEntryPerBuffer')
      for entry in @entries when entry.URI is newEntry.URI
        entry.destroy()
    else
      for entry in @entries when entry.isAtSameRow(newEntry)
        entry.destroy()

    @entries.push(newEntry)
    # Only when we are allowed to modify index, we can safely remove @entries.
    if setIndexToHead ? true
      @removeInvalidEntries()
      @setIndexToHead()

  uniqueByBuffer: ->
    return unless @entries.length
    buffers = []
    for entry in @entries.slice().reverse()
      URI = entry.URI
      if URI in buffers
        entry.destroy()
      else
        buffers.push(URI)
    @removeInvalidEntries()
    @setIndexToHead()

  removeInvalidEntries: ->
    # Scrub invalid
    for entry in @entries when not entry.isValid()
      entry.destroy()
    @entries = @entries.filter (entry) -> entry.isValid()

    # Remove if exceeds max
    removeCount = @entries.length - settings.get('max')
    if removeCount > 0
      removed = @entries.splice(0, removeCount)
      entry.destroy() for entry in removed

  inspect: (msg) ->
    ary =
      for e, i in @entries
        s = if (i is @index) then "> " else "  "
        "#{s}#{i}: #{e.inspect()}"
    ary.push "> #{@index}:" if (@index is @entries.length)
    ary.join("\n")

module.exports = History
