fs   = require 'fs'
path = require 'path'

# Wrapper class to wrap Point or Marker.
# We can't call `editor::markBufferPosition` on destroyed editor.
# So We need to use Point instead of Marker for destroyed editor.
module.exports =
class Entry
  destroyed: false
  marker: null

  constructor: (@editor, @point, @URI) ->
    if @editor.isAlive()
      @marker = @editor.markBufferPosition @point, invalidate: 'never', persistent: false

  destroy: ->
    @marker?.destroy()
    @destroyed = true

  isValid: ->
    fs.existsSync @URI

  isDestroyed: ->
    @destroyed

  getPoint: ->
    if @editor.isAlive()
      @point = @marker.getStartBufferPosition()
    @point

  getInfo: -> {@URI, point: @getPoint()}

  inspect: ->
    {URI, point} = @getInfo()
    "#{point}, #{path.basename(URI)}"

  isSameRow: ({URI, point}) ->
    (URI is @URI) and (point.row is @point.row)
