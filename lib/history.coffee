_        = require 'underscore-plus'
Entry    = require './entry'
settings = require './settings'
{debug} = require './utils'

class History
  entries: []
  index: 0

  constructor: (@max) ->
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

  isOldest: ->
    @isEmpty() or @index is 0

  isNewest: ->
    @isEmpty() or @index >= (@entries.length - 1)

  isEmpty:  ->
    @entries.length is 0

  rename: (oldURI, newURI) ->
    for e in @entries when e.URI is oldURI
      e.setURI(newURI)

  get: (direction='current') ->
    switch direction
      when 'next'
        if @isNewest()
          @dump "Newest"
          return
        @getValid direction
      when 'prev'
        if @isOldest()
          @dump "Oldest"
          return
        @getValid direction
      when 'current'
        @entries[@index]

  getValid: (direction) ->
    until @isEmpty()
      switch direction
        when 'next'
          break if @isNewest()
          @index += 1
        when 'prev'
          break if @isOldest()
          @index -= 1

      entry = @get()
      return entry if entry.isValid()

      debug "URI not exist: #{entry.URI} or Buffer closed"
      @remove(@index)
      if direction is 'next'
        @index -= 1

  remove: (index, count=1) ->
    entries = @entries.splice(index, count)
    for e in entries
      debug "  Destroy: #{e.inspect()}"
      e.destroy()
    entries

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
  add: ({editor, point, URI, setIndexToHead, dumpMessage}) ->
    setIndexToHead ?= true
    newEntry = new Entry(editor, point, URI)

    for entry, i in @entries
      if entry.isAtSameRow newEntry
        entry.destroy()
        # adjust @index for deletion.
        @index -= 1 if i <= @index

    @entries = _.reject @entries, (entry) -> entry.isDestroyed()
    @entries.push newEntry

    if @entries.length > @max
      @remove 0, (@entries.length - @max)

    if setIndexToHead
      @index = @entries.length

    if dumpMessage?
      @dump dumpMessage

  dump: (msg, force=false) ->
    unless force or settings.get('debug')
      return
    console.log "# cursor-history: #{msg}" if msg
    entries = @entries.map(
      ((e, i) =>
        if i is @index
          "> #{i}: #{e.inspect()}"
        else
          "  #{i}: #{e.inspect()}"), this)
    entries.push "> #{@index}:" unless @get()
    console.log entries.join("\n"), "\n\n"

module.exports = History
