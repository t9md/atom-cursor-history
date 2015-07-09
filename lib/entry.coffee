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

  constructor: (editor, @point, @URI) ->
    @editorAlive = editor.isAlive()
    if @editorAlive
      @subscriptions = new CompositeDisposable
      @subscriptions.add editor.onDidDestroy =>
        @editorAlive = false
        @marker?.destroy()
        @marker = null
        @subscriptions.dispose()
        @subscriptions = null
      @marker = editor.markBufferPosition @point, invalidate: 'never', persistent: false
      @subscriptions.add @marker.onDidChange ({newHeadBufferPosition}) =>
        @point = newHeadBufferPosition

  destroy: ->
    @marker?.destroy()
    @marker = null
    @subscriptions?.dispose()
    @subscriptions = null
    @destroyed = true

  isValid: ->
    if settings.get('excludeClosedBuffer')
      fs.existsSync(@URI) and @editorAlive
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
