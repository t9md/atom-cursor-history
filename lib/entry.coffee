fs       = require 'fs'
settings = require './settings'
path     = null

# Wrapper class to wrap Point or Marker.
# We can't call `editor::markBufferPosition` on destroyed editor.
# So We need to use Point instead of Marker for destroyed editor.
module.exports =
class Entry
  destroyed:  false
  marker:     null
  disposable: null

  constructor: (@editor, @point, @URI) ->
    if @editor.isAlive()
      @marker = @editor.markBufferPosition @point, invalidate: 'never', persistent: false
      @disposable = @marker.onDidChange ({newHeadBufferPosition}) =>
        @point = newHeadBufferPosition

  destroy: ->
    @marker?.destroy()
    @disposable?.dispose()
    @destroyed = true

  isValid: ->
    if settings.get('excludeClosedBuffer')
      fs.existsSync(@URI) and @editor.isAlive()
    else
      fs.existsSync @URI

  isDestroyed: ->
    @destroyed

  inspect: ->
    path ?= require 'path'
    "#{@point}, #{path.basename(@URI)}"

  isSameRow: (otherEntry) ->
    {URI, point} = otherEntry
    (URI is @URI) and (point.row is @point.row)
