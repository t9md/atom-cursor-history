_ = require 'underscore-plus'
{CompositeDisposable} = require 'atom'

class Settings
  cache: {}

  constructor: (@scope, @config) ->
    @disposables = new CompositeDisposable

    # Inject order props to display orderd in setting-view
    for name, i in Object.keys(@config)
      @config[name].order = i

    for key, object of @config
      object.type = switch
        when Number.isInteger(object.default) then 'integer'
        when typeof(object.default) is 'boolean' then 'boolean'
        when typeof(object.default) is 'string' then 'string'
        when Array.isArray(object.default) then 'array'

  destroy: ->
    @disposables.dispose()

  notifyAndDelete: (params...) ->
    paramsToDelete = (param for param in params when @has(param))
    return if paramsToDelete.length is 0

    content = [
      "#{@scope}: Config options deprecated.  ",
      "Automatically removed from your `connfig.cson`  "
    ]
    for param in paramsToDelete
      @delete(param)
      content.push "- `#{param}`"
    atom.notifications.addWarning content.join("\n"), dismissable: true

  notifyAndRename: (oldName, newName) ->
    return unless @has(oldName)

    @set(newName, @get(oldName))
    @delete(oldName)
    content = [
      "#{@scope}: Config options renamed.  ",
      "Automatically renamed in your `connfig.cson`  "
      " - `#{oldName}` to #{newName}"
    ]
    atom.notifications.addWarning content.join("\n"), dismissable: true

  has: (param) ->
    param of atom.config.get(@scope)

  delete: (param) ->
    @set(param, undefined)

  setCachableParams: (params) ->
    @cachableParams = params

  get: (param) ->
    atom.config.get("#{@scope}.#{param}")

  set: (param, value) ->
    atom.config.set "#{@scope}.#{param}", value

  toggle: (param) ->
    @set(param, not @get(param))

  observe: (param, fn) ->
    @disposables.add(atom.config.observe("#{@scope}.#{param}", fn))

module.exports = new Settings 'cursor-history',
  max:
    default: 100
    minimum: 1
    description: "number of history to keep"
  rowDeltaToRemember:
    default: 4
    minimum: 0
    description: "Save history when row delta was greater than this value"
  columnDeltaToRemember:
    default: 9999
    minimum: 0
    description: "Save history when cursor moved within same row and column delta was greater than this value"
  excludeClosedBuffer:
    default: false
    description: "Don't open closed Buffer on history excursion"
  keepSingleEntryPerBuffer:
    default: false
    description: 'Keep latest entry only per buffer'
  searchAllPanes:
    default: true
    description: "Search existing buffer from all panes before opening new editor"
  flashOnLand:
    default: false
    description: "flash cursor on land"
  ignoreCommands:
    default: ['command-palette:toggle']
    items: type: 'string'
    description: 'list of commands to exclude from history tracking.'
  debug:
    default: false
