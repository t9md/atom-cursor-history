settings  = require './settings'

module.exports =
class Flasher
  @flash: (editor, range) =>
    marker = editor.markBufferRange range,
      invalidate: 'never'
      persistent: false

    color = settings.get('flashColor')
    @decoration = editor.decorateMarker marker,
      type: 'line'
      class: "cursor-history-#{color}"

    @timeoutID = setTimeout  =>
      @decoration.getMarker().destroy()
    , settings.get('flashDurationMilliSeconds')

  @clear: =>
    @decoration?.getMarker().destroy()
    clearTimeout @timeoutID
