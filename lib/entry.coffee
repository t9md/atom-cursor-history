{CompositeDisposable} = require 'atom'
existsSync = null
path = null

# Wrapper for Point or Marker.
#  For alive editor, use Marker to track up to date position.
#  For destroyed editor, use Point.
module.exports =
class Entry
  constructor: (editor, @point, @URI) ->
    @destroyed = false
    return unless editor.isAlive()

    @editor = editor
    @subscriptions = new CompositeDisposable
    @marker = @editor.markBufferPosition(@point)
    @subscriptions.add @marker.onDidChange ({newHeadBufferPosition}) =>
      @point = newHeadBufferPosition

    @subscriptions.add @editor.onDidDestroy =>
      @unSubscribe()

  unSubscribe: ->
    @subscriptions.dispose()
    {@editor, @subscriptions} = {}

  destroy: ->
    @unSubscribe() if @editor?
    @destroyed = true
    @marker?.destroy()
    {@point, @URI, @marker} = {}

  isDestroyed: ->
    @destroyed

  isValid: ->
    return false if @isDestroyed()
    existsSync ?= require('fs').existsSync

    if atom.config.get('cursor-history.excludeClosedBuffer')
      @editor?.isAlive() and existsSync(@URI)
    else
      existsSync(@URI)

  isAtSameRow: (otherEntry) ->
    if otherEntry.point? and @point?
      (otherEntry.URI is @URI) and (otherEntry.point.row is @point.row)
    else
      false

  inspect: ->
    path ?= require 'path'
    s = "#{@point}, #{path.basename(@URI)}"
    s += ' [invalid]' unless @isValid()
    s
