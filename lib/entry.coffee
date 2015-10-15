# Refactoring status: 100%
{CompositeDisposable} = require 'atom'
fs       = require 'fs'
settings = require './settings'
path = null

# Wrapper for Point or Marker.
#  For alive editor, use Marker to track up to date position.
#  For destroyed editor, use Point.
class Entry
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
      @unSubscribe()

  unSubscribe: ->
    @editor = null
    @subscriptions.dispose()
    @subscriptions = null

  destroy: ->
    @unSubscribe() if @editor?
    @destroyed = true
    {@point, @URI} = {}

  isDestroyed: ->
    @destroyed

  setURI: (@URI) ->

  isValid: ->
    return false if @isDestroyed()

    if settings.get('excludeClosedBuffer')
      @editor?.isAlive() and fs.existsSync(@URI)
    else
      fs.existsSync @URI

  isAtSameRow: ({URI, point}) ->
    if point? and @point?
      (URI is @URI) and (point.row is @point.row)
    else
      false

  inspect: ->
    path ?= require 'path'
    s = "#{@point}, #{path.basename(@URI)}"
    s += ' [invalid]' unless @isValid()
    s

module.exports = Entry
