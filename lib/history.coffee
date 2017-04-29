Entry = require './entry'

findEditorForPaneByURI = (pane, URI) ->
  for item in pane.getItems() when atom.workspace.isTextEditor(item)
    return item if item.getURI() is URI

module.exports =
class History
  constructor: (@createLocation) ->
    @init()
    @configObserver = atom.config.observe 'cursor-history.keepSingleEntryPerBuffer', (newValue) =>
      @uniqueByBuffer() if newValue

  init: ->
    @index = 0
    @entries = []

  clear: ->
    entry.destroy() for entry in @entries
    @init()

  destroy: ->
    @configObserver.dispose()
    entry.destroy() for entry in @entries
    [@index, @entries, @configObserver] = []

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
  add: (location, {subject, setIndexToHead}={}) ->
    if atom.config.get('cursor-history.debug')
      @log("#{subject} [#{location.type}]")

    {editor, point, URI} = location
    newEntry = new Entry(editor, point, URI)

    if atom.config.get('cursor-history.keepSingleEntryPerBuffer')
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
    removeCount = @entries.length - atom.config.get('cursor-history.max')
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

  log: (msg) ->
    console.log """
      # cursor-history: #{msg}
      #{@inspect()}\n\n
      """

  jump: (editor, direction, {withinEditor}={}) ->
    wasAtHead = @isIndexAtHead()
    if withinEditor
      entry = @get(direction, URI: editor.getURI())
    else
      entry = @get(direction)

    return unless entry?
    # FIXME, Explicitly preserve point, URI by setting independent value,
    # since its might be set null if entry.isAtSameRow()
    {point, URI} = entry

    needToLog = true
    if (direction is 'prev') and wasAtHead
      location = @createLocation(editor, 'prev')
      @add(location, setIndexToHead: false, subject: "Save head position")
      needToLog = false

    activePane = atom.workspace.getActivePane()
    if editor.getURI() is URI
      @land(editor, point, direction, log: needToLog)
    else if item = findEditorForPaneByURI(activePane, URI)
      activePane.activateItem(item)
      @land(item, point, direction, forceFlash: true, log: needToLog)
    else
      searchAllPanes = atom.config.get('cursor-history.searchAllPanes')
      atom.workspace.open(URI, {searchAllPanes}).then (editor) =>
        @land(editor, point, direction, forceFlash: true, log: needToLog)

  land: (editor, point, direction, options={}) ->
    originalRow = editor.getCursorBufferPosition().row
    editor.setCursorBufferPosition(point, autoscroll: false)
    editor.scrollToCursorPosition(center: true)

    if atom.config.get('cursor-history.flashOnLand')
      if options.forceFlash or (originalRow isnt point.row)
        @flash(editor)

    if atom.config.get('cursor-history.debug') and options.log
      @log(direction)

  flashMarker: null
  flash: (editor) ->
    @flashMarker?.destroy()
    cursorPosition = editor.getCursorBufferPosition()
    @flashMarker = editor.markBufferPosition(cursorPosition)
    decorationOptions = {type: 'line', class: 'cursor-history-flash-line'}
    editor.decorateMarker(@flashMarker, decorationOptions)

    destroyMarker = =>
      disposable?.destroy()
      disposable = null
      @flashMarker?.destroy()

    disposable = editor.onDidChangeCursorPosition(destroyMarker)
    # [NOTE] animation-duration has to be shorter than this value(1sec)
    setTimeout(destroyMarker, 1000)
