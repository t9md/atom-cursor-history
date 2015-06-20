{CompositeDisposable, Disposable, TextEditor, Emitter} = require 'atom'
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

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @editorSubscriptions = {}
    @history = new History settings.get('max')

    @rowDeltaToRemember = settings.get('rowDeltaToRemember')
    settings.onDidChange 'rowDeltaToRemember', ({newValue}) =>
      @rowDeltaToRemember = newValue

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @jump('Next')
      'cursor-history:prev':  => @jump('Prev')
      'cursor-history:clear': => @clear()
      'cursor-history:dump':  => @dump()
      'cursor-history:toggle-debug': => settings.toggle 'debug', log: true

    modalPanelContainer = atom.workspace.panelContainers['modal']
    @subscriptions.add modalPanelContainer.onDidAddPanel ({panel, index}) =>
      # itemKind in ['GoToView', 'GoBackView', 'FileView', 'ProjectView']
      itemKind = panel.getItem().constructor.name
      return unless itemKind in ['FileView', 'ProjectView']
      switch itemKind
        when 'FileView'
          @handleSymbolsViewFileView panel
        when 'ProjectView'
          @handleSymbolsViewProjectView panel

    @observeTextEditor()

    @subscriptions.add atom.workspace.observeActivePaneItem (item) =>
      if item instanceof TextEditor and item.getURI()
        @handlePaneItemChanged item

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item}) =>
      if item instanceof TextEditor and item.getURI()
        LastEditor.saveDestroyedEditor item

  observeTextEditor: ->
    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @editorSubscriptions[editor.id] = new CompositeDisposable
      @handleChangePath(editor)

      @editorSubscriptions[editor.id].add editor.onDidChangeCursorPosition (event) =>
        return if @isLocked() # for performance
        return if event.oldBufferPosition.row is event.newBufferPosition.row # for performance.
        setTimeout =>
          # When symbols-view's modal panel shown, we lock() but its delayed.
          # So checking lock state here is important.
          return if @isLocked()
          @handleCursorMoved event
        , 300

      @editorSubscriptions[editor.id].add editor.onDidDestroy =>
        @editorSubscriptions[editor.id]?.dispose()
        delete @editorSubscriptions[editor.id]

  deactivate: ->
    for editorID, disposables of @editorSubscriptions
      disposables.dispose()
    @editorSubscriptions = null
    @subscriptions.dispose()
    settings.dispose()
    @history?.destroy()
    @history = null

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
      @history.add editor, point, lastURI, dumpMessage: "[Pane item changed] save history"

    @lastEditor.set item
    @debug "set LastEditor #{path.basename(item.getURI())}"

  handleCursorMoved: ({oldBufferPosition, newBufferPosition, cursor}) ->
    editor = cursor.editor
    return if editor.hasMultipleCursors()
    return unless URI = editor.getURI()

    if @needRemember(oldBufferPosition, newBufferPosition)
      @history.add editor, oldBufferPosition, URI, dumpMessage: "[Cursor moved] save history"

  needRemember: (oldBufferPosition, newBufferPosition) ->
    # console.log [oldBufferPosition, newBufferPosition]
    # Line number delata exceeds or not.
    Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember

  withPanel: (panel, {onShow, onHide}) ->
    [oldEditor, oldPoint, newEditor, newPoint] = []
    panelSubscription = panel.onDidChangeVisible (visible) =>
      if visible
        @lock()
        {editor: oldEditor, point: oldPoint} = onShow()
      else
        # ProjectView delayed changing cursor position after panel hidden(),
        setTimeout =>
          {editor: newEditor, point: newPoint} = onHide()

          # FIXME: oldPoint sometimes became undefined, so need to guard
          if oldPoint and newPoint and @needRemember(oldPoint, newPoint)
            @history.add oldEditor, oldPoint, oldEditor.getURI(), dumpMessage: "[Cursor moved] save history"
          @unLock()
        , 300

    @subscriptions.add panel.onDidDestroy ->
      panelSubscription.dispose()

  handleSymbolsViewFileView: (panel) ->
    @withPanel panel,
      onShow: =>
        # At the timing symbol-views panel show, first item in symobls
        # already selected(this mean cursor position have changed).
        # So we can't use TexitEditor::getCursorBufferPosition(), fotunately,
        # symbols-view serialize buffer state initaially, we use this.
        editor = @getEditor()
        point  = panel.getItem().initialState?.bufferRanges[0].start
        {editor, point}
      onHide: =>
        editor = @getEditor()
        point  = editor.getCursorBufferPosition()
        {editor, point}

  handleSymbolsViewProjectView: (panel) ->
    @withPanel panel,
      onShow: =>
        editor = @getEditor()
        point  = editor.getCursorBufferPosition()
        {editor, point}
      onHide: =>
        editor = @getEditor()
        point  = editor.getCursorBufferPosition()
        {editor, point}

  lock:     -> @locked = true
  unLock:   -> @locked = false
  isLocked: -> @locked

  clear: -> @history.clear()

  jump: (direction) ->
    # Settings tab is not TextEditor instance.
    return unless activeEditor = @getEditor()
    return unless entry = @history["get#{direction}"]()

    if direction is 'Prev' and @history.isNewest()
      point = activeEditor.getCursorBufferPosition()
      URI   = activeEditor.getURI()
      @history.pushToHead activeEditor, point, URI

    @lock()

    {URI, point} = entry

    if activeEditor.getURI() is URI # Same pane.
      # Intentionally disable `autoscroll` to set cursor position middle of
      # screen afterward.
      activeEditor.setCursorBufferPosition point, autoscroll: false
      # Adjust cursor position to middle of screen.
      activeEditor.scrollToCursorPosition()
      @land direction
    else
      # Jump to different pane
      options =
        searchAllPanes: settings.get('searchAllPanes')

      atom.workspace.open(URI, options).done (editor) =>
        editor.scrollToBufferPosition(point, center: true)
        editor.setCursorBufferPosition(point)
        @land direction

  land: (direction) ->
    @unLock()
    Flasher.flash() if settings.get('flashOnLand')
    @history.dump direction

  debug: (msg) ->
    return unless settings.get('debug')
    console.log msg

  getEditor: ->
    atom.workspace.getActiveTextEditor()

  dump: ->
    @history.dump '', true
