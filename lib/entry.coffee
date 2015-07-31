{CompositeDisposable} = require 'atom'
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
    # We need @editor only when editor.isAlive() to update @point.
    unless @editor.isAlive()
      @editor = null
      return

    @subscriptions = new CompositeDisposable
    @marker = @editor.markBufferPosition @point,
      invalidate: 'never',
      persistent: false

    @subscriptions.add @marker.onDidChange ({newHeadBufferPosition}) =>
      @point = newHeadBufferPosition

    @subscriptions.add @editor.onDidDestroy =>
      @releaseEditor()

  releaseEditor: ->
    @editor = null
    @marker.destroy()
    @marker = null
    @subscriptions.dispose()
    @subscriptions = null

  destroy: ->
    if @editor?.isAlive()
      @releaseEditor()
    @destroyed = true

  isValid: ->
    if settings.get('excludeClosedBuffer')
      fs.existsSync(@URI) and @editor?.isAlive()
    else
      fs.existsSync @URI

  isDestroyed: ->
    @destroyed

  inspect: ->
    path ?= require 'path'
    "#{@point}, #{path.basename(@URI)}"

  isSameRow: (otherEntry) ->
    {URI, point} = otherEntry
    (URI is @URI) and (point and @point) and (point.row is @point.row)
