path = require 'path'
# We need to freeze @lastEditor info maunually since
# `onDidChangeCursorPosition` is triggered asynchronously and
# not predictable of timing(after/before/in pane changing).
module.exports =
class LastEditor
  @destroyedEditors: {}

  @inspectEditor: (editor) ->
    "#{editor.getCursorBufferPosition()} #{path.basename(editor.getURI())}"

  @saveDestroyedEditor: (editor) ->
    console.log "Save Destroyed #{@inspectEditor(editor)}"
    @destroyedEditors[editor.getURI()] = editor.getCursorBufferPosition()

  constructor: (editor) ->
    @init editor

  init: (@editor) ->
    @URI = @editor.getURI()
    @update()

  update: ->
    if @editor.isAlive()
      @point = @editor.getCursorBufferPosition()
    else
      @point = @constructor.destroyedEditors[@URI]
      console.log "retrieve Destroyed #{@point}, #{path.basename(@URI)}"

    @getInfo()

  getInfo: -> {@URI, @point, @editor}
