module.exports =
class CursorHistory
  constructor: ->
    @initialize()

  reset: -> @initialize()

  initialize: ->
    @index   = -1
    @entries = []
    @max = atom.config.get('cursor-history.max')

  getLength: -> @entries.length

  next: ->
    if @index + 1 is @entries.length
      console.log "newest"
      return
    @index = @index + 1
    @get @index

  prev: ->
    if @index - 1 is -1
      console.log "oldest"
      return
    @index = @index - 1
    @get @index

  get: (index) ->
    @entries[index]

  add: (entry) ->
    if @index + 1 is @max
      console.log 'max'
      return
    @index = @index + 1
    @entries[@index] = entry
    @entries.length = @index + 1
    console.log @dump()

  dump: ->
    console.log [ @entries, @index, @entries.length ]

  serialize: () ->
