path = require 'path'

# We cant' call getCursorBufferPosition() on destroyed TextEditor.
# So this LastEditor provide consitent way to get latest cursor position
# by wrapping Alive() editor and destroyed editor.

module.exports =
class LastEditor
  @destroyedEditors: {}

  @rename: (oldURI, newURI) ->
    for URI, point of @destroyedEditors when URI is oldURI
      @destroyedEditors[newURI] = point
      delete @destroyedEditors[URI]

  @saveDestroyedEditor: (editor) ->
    @destroyedEditors[editor.getURI()] = editor.getCursorBufferPosition()

  constructor: (editor) ->
    @set editor

  set: (@editor) ->
    @URI = @editor.getURI()

  rename: (oldURI, newURI) ->
    @URI = newURI if @URI is oldURI
    @constructor.rename oldURI, newURI

  getPoint: ->
    if @editor.isAlive()
      @editor.getCursorBufferPosition()
    else
      @constructor.destroyedEditors[@URI]

  getInfo: ->
    {@editor, point: @getPoint(), @URI}
