
settings =
  config:
    max:
      order: 1
      type: 'integer'
      default: 100
      minimum: 1
      description: "number of history to remember"
    rowDeltaToRemember:
      order: 2
      type: 'integer'
      default: 4
      minimum: 0
      description: "Only if dirrerence of cursor row exceed this value, cursor position is saved to history"
    keepPane:
      order: 3
      type: 'boolean'
      default: false
      description: "Open history entry always on same pane."
    flashOnLand:
      order: 4
      type: 'boolean'
      default: false
      description: "flash cursor line on land"
    flashDurationMilliSeconds:
      order: 5
      type: 'integer'
      default: 200
      description: "Duration for flash"
    flashColor:
      order: 6
      type: 'string'
      default: 'info'
      enum: ['info', 'success', 'warning', 'error', 'highlight', 'selected']
      description: 'flash color style, correspoinding to @background-color-#{flashColor}: see `styleguide:show`'
    debug:
      order: 7
      type: 'boolean'
      default: false
      description: "Output history on console.log"

# Borrowed from vim-mode settigs.coffee
Object.keys(settings.config).forEach (key) ->
  settings[key] = (action='get') ->
    switch action
      when 'get'
        atom.config.get('cursor-history.'+key)
      when 'toggle'
        atom.config.toggle('cursor-history.'+key)

module.exports = settings
