{CompositeDisposable} = require 'atom'
fs       = require 'fs'
settings = require './settings'
path = null

# Wrapper class to wrap Point or Marker.
# We can't call `editor::markBufferPosition` on destroyed editor.
# So We need to use Point instead of Marker for destroyed editor.
module.exports =
class Entry
  destroyed: false
  subscriptions: null

  constructor: (editor, @point, @URI) ->
    # We need @editor only when editor.isAlive() to update @point.
    return unless editor.isAlive()

    @editor = editor
    @subscriptions = new CompositeDisposable
    marker = @editor.markBufferPosition @point,
      invalidate: 'never',
      persistent: false

    @subscriptions.add marker.onDidChange ({newHeadBufferPosition}) =>
      @point = newHeadBufferPosition

    @subscriptions.add @editor.onDidDestroy =>
      marker.destroy()
      @releaseEditor()

  releaseEditor: ->
    @editor = null
    @subscriptions.dispose()
    @subscriptions = null

  destroy: ->
    @releaseEditor() if @editor?.isAlive()
    @destroyed = true
    {@point, @URI} = {}

  isDestroyed: ->
    @destroyed

  setURI: (@URI) ->

  isValid: ->
    if settings.get('excludeClosedBuffer')
      fs.existsSync(@URI) and @editor?.isAlive()
    else
      fs.existsSync @URI

  inspect: ->
    path ?= require 'path'
    "#{@point}, #{path.basename(@URI)}"

  isAtSameRow: (otherEntry) ->
    {URI, point} = otherEntry
    if point? and @point?
      (URI is @URI) and (point.row is @point.row)
    else
      false
