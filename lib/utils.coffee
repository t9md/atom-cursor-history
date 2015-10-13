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

module.exports = {
  debug
  delay
  reportLocation
}
