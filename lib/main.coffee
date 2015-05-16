{CompositeDisposable, TextEditor} = require 'atom'
path = require 'path'

Config =
  max:
    type: 'integer'
    default: 100
    minimum: 1
    description: "number of history to remember"
  rowDeltaToRemember:
    type: 'integer'
    default: 4
    minimum: 0
    description: "Only if dirrerence of cursor row exceed this value, cursor position is saved to history"
  debug:
    type: 'boolean'
    default: false
    description: "Output history on console.log"

# We need to freeze @lastEditor info maunually since
# `onDidChangeCursorPosition` is triggered asynchronously and
# not predictable of timing(after/before/in pane changing).
class LastEditor
  @destroyedEditors: {}

  @inspectEditor: (editor) ->
    "#{editor.getCursorBufferPosition()} #{path.basename(editor.getURI())}"

  @saveDestroyedEditor: (editor) ->
    console.log "Save Destroyed #{@inspectEditor(editor)}"
    @destroyedEditors[editor.getURI()] = editor.getCursorBufferPosition()

  constructor: (editor) ->
    @set editor
    @update()

  set: (@editor) ->

  update: ->
    if @editor.isAlive()
      @URI   = @editor.getURI()
      @point = @editor.getCursorBufferPosition()
    else
      console.log "retrieve Destroyed #{@point}, #{path.basename(@URI)}"
      @point = @constructor.destroyedEditors[@URI]

  getInfo: -> {@URI, @point, @editor}

module.exports =
  history: null
  direction: null
  subscriptions: null
  lastEditor: null
  config: Config

  debug: (msg) ->
    return unless atom.config.get 'cursor-history.debug'
    console.log msg

  activate: (state) ->
    @subscriptions = new CompositeDisposable

    History = require './history'
    @history = new History atom.config.get('cursor-history.max')

    @rowDeltaToRemember = atom.config.get 'cursor-history.rowDeltaToRemember'
    @subscriptions.add atom.config.onDidChange 'cursor-history.rowDeltaToRemember', ({newValue}) =>
      @rowDeltaToRemember = newValue

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @next()
      'cursor-history:prev':  => @prev()
      'cursor-history:clear': => @clear()
      'cursor-history:dump':  => @dump()
      'cursor-history:toggle-debug': => @toggleDebug()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @subscriptions.add editor.onDidChangeCursorPosition @handleCursorMoved.bind(@)

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item}) =>
      if item instanceof TextEditor and item.getURI()
        LastEditor.saveDestroyedEditor item

    @subscriptions.add atom.workspace.observeActivePaneItem @handlePaneChanged.bind(@)

  inspectEditor: (editor) ->
    "#{editor.getCursorBufferPosition()} #{path.basename(editor.getURI())}"

  dump: ->
    console.log @lastEditor.getInfo().URI
    @history.dump '', true

  toggleDebug: ->
    atom.config.toggle 'cursor-history.debug'
    state = atom.config.get('cursor-history.debug') and "enabled" or "disabled"
    console.log "cursor-history: debug #{state}"

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()

  serialize: ->
    @history?.serialize()

  handlePaneChanged: (item) ->
    return unless item instanceof TextEditor
    return unless newURI = item.getURI()

    # We need to track former active pane to know cursor position when active pane was changed.
    unless @lastEditor
      @lastEditor = new LastEditor(item)
      return

    @debug "# Pane Changed dir = #{@direction} #{@inspectEditor(@lastEditor.editor)} -> #{@inspectEditor(item)}"
    @lastEditor.update()
    {editor, URI, point} = @lastEditor.getInfo()

    # # We save history only if URI(filePath) is different.
    @saveHistory editor, point, URI, => newURI isnt URI
    @lastEditor.set item

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    editor = cursor.editor
    return if editor.hasMultipleCursors()
    # [FIXME] Currently buffer without URI is simply ignored.
    return unless URI = editor.getURI()

    @debug "CursorMoved #{oldBufferPosition} -> #{newBufferPosition} #{path.basename(URI)}"
    lastURI = @lastEditor.getInfo().URI
    @saveHistory editor, oldBufferPosition, URI, =>
      console.log [lastURI, URI]
      if lastURI isnt URI
        @lastEditor.update()
        # Just after pane was changed `onDidChangeCursorPosition` is triggered.
        # But this is not movement within same file(URI) and is movement from another
        # pane to this pane, we ignore this since saving this is counter intuitive.
        @debug "# Pane changed, ignore this cursor movement"
        return false
      @needRemember(oldBufferPosition, newBufferPosition, cursor)

  saveHistory: (editor, point, URI, suffice) ->
    args = [editor, point, URI]
    if @direction
      if @direction is 'prev' and @history.isNewest()
        @history.pushToHead args...
      @direction = null
    else
      if suffice()
        @history.add args...

  needRemember: (oldBufferPosition, newBufferPosition, cursor) ->
    # Line number delata exceeds or not.
    if Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember
      return true
    else
      return false

  next:  -> @jump 'next'
  prev:  -> @jump 'prev'
  clear: -> @history.clear()

  jump: (direction) ->
    # Settings tab is not TextEditor instance.
    activeEditor = atom.workspace.getActiveTextEditor()
    return unless activeEditor

    entry = @history[direction]()
    return unless entry

    # Used to track why cursor moved.
    # Order matter, DONT set @direction before `return`.
    #  - next: by `cursor-history:next` command
    #  - prev: by `cursor-history:prev` command
    #  - null: normal movement.
    @direction = direction

    {URI, point} = entry.getInfo()
    if activeEditor.getURI() is URI
      # Jump within active editor.
      activeEditor.setCursorBufferPosition point

    else
      atom.workspace.open(URI, searchAllPanes: true).done (editor) =>
        # Jump to another another file.
        editor.setCursorBufferPosition point
