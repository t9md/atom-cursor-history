settings = require './settings'

debug = (msg) ->
  return unless settings.get('debug')
  console.log msg

delay = (ms, fn) ->
  setTimeout ->
    fn()
  , ms

reportLocation = (location) ->
  {point, URI, type} = location
  [type, point.toString(), URI]

getLocation = (type, editor) ->
  point = editor.getCursorBufferPosition()
  URI   = editor.getURI()
  {editor, point, URI, type}

module.exports = {
  debug
  delay
  reportLocation
  getLocation
}
