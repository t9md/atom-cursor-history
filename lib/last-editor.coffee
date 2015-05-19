path = require 'path'

# We cant' call getCursorBufferPosition() on destroyed TextEditor.
# So this LastEditor provide consitent way to get latest cursor position
# by wrapping Alive() editor and destroyed editor.

module.exports =
class LastEditor
  @destroyedEditors: {}

  @inspectEditor: (editor) ->
    "#{editor.getCursorBufferPosition()} #{path.basename(editor.getURI())}"

  @saveDestroyedEditor: (editor) ->
    # console.log "Save Destroyed #{@inspectEditor(editor)}"
    @destroyedEditors[editor.getURI()] = editor.getCursorBufferPosition()

  constructor: ->

  set: (@editor) ->
    @URI = @editor.getURI()
    @update()

  update: ->
    if @editor.isAlive()
      @point = @editor.getCursorBufferPosition()
    else
      @point = @constructor.destroyedEditors[@URI]
      console.log "retrieve Destroyed #{@point}, #{path.basename(@URI)}"

  getInfo: ->
    @update()
    {@URI, @point, @editor}
