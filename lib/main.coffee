{CompositeDisposable, TextEditor} = require 'atom'
History = require './history'
path = require 'path'

module.exports =
  history: null
  direction: null
  subscriptions: null
  lastEditor: null

  config:
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

  debug: (msg) ->
    return unless atom.config.get 'cursor-history.debug'
    console.log msg

  activate: (state) ->
    @subscriptions = new CompositeDisposable
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

    @subscriptions.add atom.workspace.observeActivePaneItem @handlePaneChanged.bind(@)

  dumpLastEditor: ->
    URI   = @lastEditor.getURI()
    point = @lastEditor.getCursorBufferPosition()
    @debug "lastEditor = #{point} #{URI}, "

  inspectEditor: (editor) ->
    URI   = @lastEditor.getURI()
    point = @lastEditor.getCursorBufferPosition()
    "#{point} #{path.basename(URI)}"

  dump: ->
    @dumpLastEditor()
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
    return unless item.getURI()

    # We need to track former active pane to know cursor position when active pane was changed.
    unless @lastEditor
      @lastEditor = item
      return

    @debug "# PaneItem Changed: dir = #{@direction}"
    @debug " From: #{@inspectEditor(@lastEditor)}"
    @debug " To:   #{@inspectEditor(item)}"

    URI   = @lastEditor.getURI()
    point = @lastEditor.getCursorBufferPosition()
    @saveHistory @lastEditor, point, URI, => item.getURI() isnt URI
    @lastEditor = item

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    editor = cursor.editor
    return if editor.hasMultipleCursors()

    # [FIXME] currently buffer without URI is simply ignored.
    # is there any way to support 'untitled' buffer?
    return unless URI = editor.getURI()

    @debug "CursorMoved #{oldBufferPosition} -> #{newBufferPosition} #{path.basename(URI)}"

    if @lastEditor.getURI() isnt URI
      # Pane was changed, its handled by observeActivePaneItem()
      # And here we should return to avoid duplicate save.
      @debug "JUST MOVED return on cursorMoved"
      return

    fn = => @needRemember(oldBufferPosition, newBufferPosition, cursor)
    @saveHistory editor, oldBufferPosition, URI, fn

  saveHistory: (editor, oldBufferPosition, URI, fn) ->
    args = [editor, oldBufferPosition, URI]
    if @direction
      if @direction is 'prev' and @history.isNewest()
        @history.pushToHead args...
      @direction = null
    else
      return unless fn()
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

    marker = @history[direction]()
    return unless marker

    # Used to track why cursor moved.
    # Order matter, DONT set @direction before `return`.
    #  - next: by `cursor-history:next` command
    #  - prev: by `cursor-history:prev` command
    #  - null: normal movement.
    @direction = direction

    URI = marker.getProperties().URI
    point = marker.getStartBufferPosition()

    if activeEditor.getURI() is URI
      # Jump within active editor.
      activeEditor.setCursorBufferPosition point

    else
      atom.workspace.open(URI, searchAllPanes: true).done (editor) =>
        # Jump to another another file.
        editor.setCursorBufferPosition point
