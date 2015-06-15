{CompositeDisposable, TextEditor, Emitter} = require 'atom'
path = require 'path'
_    = require 'underscore-plus'

History    = require './history'
LastEditor = require './last-editor'
Flasher    = require './flasher'
settings   = require './settings'

module.exports =
  config: settings.config
  history: null
  subscriptions: null
  editorSubscriptions: null
  lastEditor: null
  locked: false

  onWillJumpToHistory: (callback) ->
    @emitter.on 'will-jump-to-history', callback

  onDidJumpToHistory:  (callback) ->
    @emitter.on 'did-jump-to-history', callback

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @editorSubscriptions = {}
    @emitter       = new Emitter
    @history       = new History settings.get('max')

    @rowDeltaToRemember = settings.get('rowDeltaToRemember')
    settings.onDidChange 'rowDeltaToRemember', ({newValue}) =>
      @rowDeltaToRemember = newValue

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @next()
      'cursor-history:prev':  => @prev()
      'cursor-history:clear': => @clear()
      'cursor-history:dump':  => @dump()
      'cursor-history:toggle-debug': => @toggleConfig('debug')
      'cursor-history:check-leak': => @checkLeak()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @editorSubscriptions[editor.id] = new CompositeDisposable
      @handleChangePath(editor)

      @editorSubscriptions[editor.id].add editor.onDidChangeCursorPosition (event) =>
        return if @isLocked()
        @handleCursorMoved event

      @editorSubscriptions[editor.id].add editor.onDidDestroy =>
        @editorSubscriptions[editor.id].dispose()
      #   delete @editorSubscriptions[editor.id]

    @subscriptions.add atom.workspace.observeActivePaneItem (item) =>
      if item instanceof TextEditor and item.getURI()
        @handlePaneItemChanged item

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item}) =>
      if item instanceof TextEditor and item.getURI()
        LastEditor.saveDestroyedEditor item

    @subscriptions.add @onWillJumpToHistory (direction) =>
      @lock()

    @subscriptions.add @onDidJumpToHistory (direction) =>
      @unLock()
      Flasher.flash() if settings.get('flashOnLand')
      @history.dump direction

  checkLeak: ->
    subTotal       = @subscriptions.disposables.size
    editorSubTotal = _.chain(@editorSubscriptions)
      .values()
      .map((e) -> e.disposables?.size)
      .filter( (e) -> e?)
      .reduce(((sum, n) -> sum + n), 0)
      .value()
    console.log "subTotal: #{subTotal}"
    console.log "editorSubTotal: #{editorSubTotal}"

  handleChangePath: (editor) ->
    orgURI = editor.getURI()

    @editorSubscriptions[editor.id].add editor.onDidChangePath =>
      newURI = editor.getURI()
      @history.rename orgURI, newURI
      @lastEditor.rename orgURI, newURI
      orgURI = newURI

  handlePaneItemChanged: (item) ->
    # We need to track former active pane to know cursor position when active pane was changed.
    @lastEditor ?= new LastEditor(item)

    {editor, point, URI: lastURI} = @lastEditor.getInfo()
    if not @isLocked() and (lastURI isnt item.getURI())
      @saveHistory editor, point, lastURI, dumpMessage: "[Pane item changed] save history"

    @lastEditor.set item
    @debug "set LastEditor #{path.basename(item.getURI())}"

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    editor = cursor.editor
    return if editor.hasMultipleCursors()
    return unless URI = editor.getURI()

    if @needRemember(oldBufferPosition, newBufferPosition, cursor)
      @saveHistory editor, oldBufferPosition, URI, dumpMessage: "[Cursor moved] save history"

  # Throttoling save to history once per 500ms.
  # When activePaneItem change and cursorMove event happened almost at once.
  # We pick activePaneItem change, and ignore cursor movement.
  # Since activePaneItem change happen before cursor movement.
  # Ignoring tail call mean ignoring cursor move happen just after pane change.
  # This is mainly for saving only target position on `symbols-view:goto-declaration` and
  # ignoring relaying position(first line of file of target position.)
  saveHistory: (editor, point, URI, options)->
    @_saveHistory ?= _.throttle(@history.add.bind(@history), 500, trailing: false)
    @_saveHistory editor, point, URI, options

  needRemember: (oldBufferPosition, newBufferPosition, cursor) ->
    # Line number delata exceeds or not.
    Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember

  lock:     -> @locked = true
  unLock:   -> @locked = false
  isLocked: -> @locked

  clear: -> @history.clear()

  next: -> @jump 'Next'
  prev: -> @jump 'Prev'

  jump: (direction) ->
    # Settings tab is not TextEditor instance.
    return unless activeEditor = @getActiveTextEditor()
    return unless entry = @history["get#{direction}"]()

    if direction is 'Prev' and @history.isNewest()
      point = activeEditor.getCursorBufferPosition()
      URI   = activeEditor.getURI()
      @history.pushToHead activeEditor, point, URI

    @emitter.emit 'will-jump-to-history', direction

    {URI, point} = entry

    if activeEditor.getURI() is URI
      # Jump within same paneItem

      # Intentionally disable `autoscroll` to set cursor position middle of
      # screen afterward.
      activeEditor.setCursorBufferPosition point, autoscroll: false
      # Adjust cursor position to middle of screen.
      activeEditor.scrollToCursorPosition()
      @emitter.emit 'did-jump-to-history', direction

    else
      # Jump to different pane
      options =
        searchAllPanes: settings.get('searchAllPanes')

        # initialLine: point.row
        # initialColumn: point.column

      atom.workspace.open(URI, options).done (editor) =>
        editor.scrollToBufferPosition(point, center: true)
        editor.setCursorBufferPosition(point)
        @emitter.emit 'did-jump-to-history', direction

    @history.dump direction

  deactivate: ->
    @subscriptions.dispose()
    for key, disposables in @editorSubscriptions
      disposables.dispose()
    @editorSubscriptions = null
    settings.dispose()
    @history?.destroy()
    @history = null

  debug: (msg) ->
    return unless settings.get('debug')
    console.log msg

  serialize: ->
    @history?.serialize()

  getActiveTextEditor: ->
    atom.workspace.getActiveTextEditor()

  dump: ->
    @history.dump '', true

  toggleConfig: (param) ->
    settings.toggle(param, true)
