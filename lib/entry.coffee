{CompositeDisposable} = require 'atom'
fs       = require 'fs'
settings = require './settings'
path = null

# Wrapper for Point or Marker.
#  For alive editor, we use marker to track updated position.
#  For destroyed editor, we use simple point instead of marker.
class Entry
  destroyed: false
  subscriptions: null

  constructor: (editor, @point, @URI) ->
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
      @editor?.isAlive() and fs.existsSync(@URI)
    else
      fs.existsSync @URI

  isAtSameRow: (otherEntry) ->
    {URI, point} = otherEntry
    if point? and @point?
      (URI is @URI) and (point.row is @point.row)
    else
      false

  inspect: ->
    path ?= require 'path'
    "#{@point}, #{path.basename(@URI)}"

module.exports = Entry
