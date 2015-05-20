path = require 'path'

# We cant' call getCursorBufferPosition() on destroyed TextEditor.
# So this LastEditor provide consitent way to get latest cursor position
# by wrapping Alive() editor and destroyed editor.

module.exports =
class LastEditor
  @destroyedEditors: {}

  @inspectEditor: (editor) ->
    "#{editor.getCursorBufferPosition()} #{path.basename(editor.getURI())}"

  @rename: (oldURI, newURI) ->
    for URI, point of @destroyedEditors when URI is oldURI
      @destroyedEditors[newURI] = point
      delete @destroyedEditors[URI]

  @saveDestroyedEditor: (editor) ->
    # console.log "Save Destroyed #{@inspectEditor(editor)}"
    @destroyedEditors[editor.getURI()] = editor.getCursorBufferPosition()

  constructor: (editor) ->
    @set editor

  set: (@editor) ->
    @URI = @editor.getURI()
    @update()

  rename: (oldURI, newURI) ->
    @URI = newURI if @URI is oldURI
    @constructor.rename oldURI, newURI

  update: ->
    if @editor.isAlive()
      @point = @editor.getCursorBufferPosition()
    else
      @point = @constructor.destroyedEditors[@URI]

  getInfo: ->
    @update()
    {@URI, @point, @editor}
