ConfigPlus = require 'atom-config-plus'

module.exports = new ConfigPlus 'cursor-history',
  max:
    order: 11
    type: 'integer'
    default: 100
    minimum: 1
    description: "number of history to remember"
  rowDeltaToRemember:
    order: 12
    type: 'integer'
    default: 4
    minimum: 0
    description: "Only if dirrerence of cursor row exceed this value, cursor position is saved to history"
  excludeClosedBuffer:
    order: 13
    type: 'boolean'
    default: false
    description: "Don't open closed Buffer on history excursion"
  searchAllPanes:
    order: 31
    type: 'boolean'
    default: true
    description: "Land to another pane or stick to same pane"
  flashOnLand:
    order: 32
    type: 'boolean'
    default: false
    description: "flash cursor line on land"
  flashDurationMilliSeconds:
    order: 33
    type: 'integer'
    default: 150
    description: "Duration for flash"
  flashColor:
    order: 34
    type: 'string'
    default: 'info'
    enum: ['info', 'success', 'warning', 'error', 'highlight', 'selected']
    description: 'flash color style, correspoinding to @background-color-{flashColor}: see `styleguide:show`'
  flashType:
    order: 35
    type: 'string'
    default: 'line'
    enum: ['line', 'word', 'point']
    description: 'Range to be flashed'
  ignoreCommands:
    order: 36
    type: 'array'
    items: type: 'string'
    default: ['command-palette:toggle']
    description: 'list of commands to exclude from history tracking.'
  debug:
    order: 99
    type: 'boolean'
    default: false
    description: "Output history on console.log"
