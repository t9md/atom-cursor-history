settings  = require './settings'
{Range} = require 'atom'

module.exports =
class Flasher
  @flash: =>
    @clear()
    editor = atom.workspace.getActiveTextEditor()
    spec =
      switch settings.get('flashType')
        when 'line'
          type: 'line'
          range: editor.getLastCursor().getCurrentLineBufferRange()
        when 'word'
          type: 'highlight'
          range: editor.getLastCursor().getCurrentWordBufferRange()
        when 'point'
          point = editor.getCursorBufferPosition()
          type: 'highlight'
          range: new Range(point, point.translate([0, 1]))

    marker = editor.markBufferRange spec.range,
      invalidate: 'never'
      persistent: false

    @decoration = editor.decorateMarker marker,
      type: spec.type
      class: "cursor-history-#{settings.get('flashColor')}"

    @timeoutID = setTimeout  =>
      @decoration.getMarker().destroy()
    , settings.get('flashDurationMilliSeconds')

  @clear: =>
    @decoration?.getMarker().destroy()
    clearTimeout @timeoutID
