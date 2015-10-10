settings = require './settings'

debug = (msg) ->
  return unless settings.get('debug')
  console.log msg

delay = (ms, fun) ->
  setTimeout ->
    fun()
  , ms

reportLocation = (location) ->
  {point, URI, type} = location
  [type, point.toString(), URI]

module.exports = {
  debug
  delay
}
