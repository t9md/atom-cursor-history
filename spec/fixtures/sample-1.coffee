# Phrase:
# ---------------------------------
  getSelectedBufferRow: (selection, which) ->
    rows = selection.getBufferRowRange()
    rows = rows.reverse() if selection.isReversed()
    [tail, head] = rows
    switch which
      when 'head' then head
      when 'tail' then tail


# Phrase:
# ---------------------------------
  isSingleColumnSelection =  (selection) ->
    selection.getBufferRange().toDelta().isEqual([0, 1])

# Phrase: Include
# ---------------------------------
# Include module(object which normaly provides set of methods) to klass
include = (klass, module) ->
  for key, value of module
    klass::[key] = value

# Phrase: scan Atom
# ---------------------------------
scan = ->
  editor1 = atom.workspace.getActiveTextEditor()
  cursor = editor1.getLastCursor()
  point = cursor.getBufferPosition()
  console.log "cursor position: #{point.toString()}"

  {selection} = cursor
  selection.selectWord()
  scanRange = cursor.getCurrentLineBufferRange()
  scanRange.start = selection.getHeadBufferPosition()
  # scanRange.start = point
  # console.log "scan #{scanRange.toString()}"
  editor1.scanInBufferRange /\s+/, scanRange, ({match, range, stop}) ->
    # console.log match
    console.log "got #{range.toString()}"
    selection.selectToBufferPosition range.end
    stop()

scan()
