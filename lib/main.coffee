{CompositeDisposable, TextEditor} = require 'atom'
path = require 'path'
_ = require 'underscore-plus'

History    = null
LastEditor = null
Flasher    = null
settings   = require './settings'

module.exports =
  config:     settings.config
  history:    null
  lastEditor: null
  locked:     false

  subscriptions: null
  editorSubscriptions: null

  # Experiment
  openTags: null

  activate: ->
    History = require './history'
    LastEditor = require './last-editor'

    @subscriptions = new CompositeDisposable
    @editorSubscriptions = {}
    @history = new History settings.get('max')

    @rowDeltaToRemember = settings.get('rowDeltaToRemember')
    settings.onDidChange 'rowDeltaToRemember', ({newValue}) =>
      @rowDeltaToRemember = newValue

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @jump('Next')
      'cursor-history:prev':  => @jump('Prev')
      'cursor-history:clear': => @history.clear()
      'cursor-history:dump':  => @dump()
      'cursor-history:toggle-debug': => settings.toggle 'debug', log: true

    @subscriptions.add @observeModalPanel()
    @subscriptions.add @observeTextEditors()
    @subscriptions.add @observeActivePaneItem()
    @subscriptions.add @observeOnWillDestroyPaneItem()

  deactivate: ->
    for editorID, disposables of @editorSubscriptions
      disposables.dispose()
    @editorSubscriptions = null
    @subscriptions.dispose()
    settings.dispose()
    @history?.destroy()
    @history = null

  extendSymbolsView: ->
    around = (decoration) ->
      (base) ->
        (params...) ->
          callback = -> base params...
          decoration ([callback].concat params)...

    withAudit = around (cb, params...) ->
      console.log "Before"
      cb()
      console.log "After"

    extendOpenTag = (view) ->
      openTag = view.openTag.bind(view)
      view.openTag = withAudit openTag
      openTag

    @openTags = {}
    atom.packages.onDidActivatePackage (pack) ->
      return unless pack.name is 'symbols-view'
      main = pack.mainModule

      @openTags['FileView']    = extendOpenTag main.createFileView()
      @openTags['ProjectView'] = extendOpenTag main.createProjectView()
      @openTags['GoToView']    = extendOpenTag main.createGoToView()
      @openTags['GoBackView']  = extendOpenTag main.createGoBackView()

  # For better handling symbols-view.
  # -------------------------
  observeModalPanel: ->
    withPanel = (panel, {onDidShow, onDidHide}) =>
      [oldEditor, oldPoint, newEditor, newPoint] = []
      panelSubscription = panel.onDidChangeVisible (visible) =>
        if visible
          @lock()
          {editor: oldEditor, point: oldPoint} = onDidShow()
        else
          # Final position is set after some delay from panel hidden.
          setTimeout =>
            {editor: newEditor, point: newPoint} = onDidHide()

            # FIXME: oldPoint sometimes became undefined, so need to guard
            if oldPoint and newPoint and @needRemember(oldPoint, newPoint)
              @history.add oldEditor, oldPoint, oldEditor.getURI(), dumpMessage: "[Cursor moved] save history"
            @unLock()
          , 300

      @subscriptions.add panel.onDidDestroy =>
        panelSubscription.dispose()

    symbolsViewHandlers =
      FileView: (panel) =>
        withPanel panel,
          # At the timing symbol-views panel show, first item in symobls
          # already selected(this mean cursor position have changed).
          # So we can't use TexitEditor::getCursorBufferPosition(), fotunately,
          # FileView serialize buffer state initaially, we use this.
          onDidShow: =>
            @debug "Shown FileView"
            editor = @getEditor()
            point  = panel.getItem().initialState?.bufferRanges[0].start
            {editor, point}
          onDidHide: =>
            @debug "Hidden FileView"
            editor = @getEditor()
            point  = @getPosition editor
            {editor, point}

      ProjectView: (panel) =>
        withPanel panel,
          onDidShow: =>
            @debug "Shown ProjectView"
            editor = @getEditor()
            point  = @getPosition editor
            {editor, point}
          onDidHide: =>
            @debug "Hidden ProjectView"
            editor = @getEditor()
            point  = @getPosition editor
            {editor, point}

    atom.workspace.panelContainers['modal'].onDidAddPanel ({panel, index}) =>
      # [CAUTION] Simply checking constructor name is not enough.
      # e.g. ProjectView is also used in `fuzzy-finder`.
      # return unless name in ['GoToView', 'GoBackView', 'FileView', 'ProjectView']
      item = panel.getItem()
      name = item.constructor.name
      if name in ['FileView', 'ProjectView'] and typeof(item.openTag) is 'function'
        symbolsViewHandlers[name]?(panel)

  observeTextEditors: ->
    onDidChangePath = (editor) =>
      oldURI = editor.getURI()

      editor.onDidChangePath =>
        newURI = editor.getURI()
        @history.rename oldURI, newURI
        @lastEditor.rename oldURI, newURI
        oldURI = newURI

    onDidChangeCursorPosition = (editor) =>
      editor.onDidChangeCursorPosition ({oldBufferPosition, newBufferPosition}) =>
        return if @isLocked() # for performance
        return if editor.hasMultipleCursors()
        return if oldBufferPosition.row is newBufferPosition.row # for performance
        return unless @needRemember(oldBufferPosition, newBufferPosition)

        setTimeout =>
          # When symbols-view's modal panel shown, we lock() but its delayed.
          # So we need lock state again here after some delay.
          return if @isLocked()
          # @debug "Move #{oldBufferPosition.toString()} -> #{newBufferPosition.toString()}"
          @history.add editor, oldBufferPosition, editor.getURI(), dumpMessage: "[Cursor moved] save history"
        , 300

    onDidDestroy = (editor) =>
      editor.onDidDestroy =>
        @editorSubscriptions[editor.id]?.dispose()
        delete @editorSubscriptions[editor.id]

    atom.workspace.observeTextEditors (editor) =>
      return unless editor.getURI()
      @editorSubscriptions[editor.id] = new CompositeDisposable
      @editorSubscriptions[editor.id].add onDidChangePath(editor)
      @editorSubscriptions[editor.id].add onDidChangeCursorPosition(editor)
      @editorSubscriptions[editor.id].add onDidDestroy(editor)

  observeActivePaneItem: ->
    handlePaneItemChanged = (item) =>
      # We need to track former active pane to know cursor position when active pane was changed.
      @lastEditor ?= new LastEditor(item)

      {editor, point, URI: lastURI} = @lastEditor.getInfo()
      if not @isLocked() and (lastURI isnt item.getURI())
        @history.add editor, point, lastURI, dumpMessage: "[Pane item changed] save history"
      @lastEditor.set item
      @debug "set LastEditor #{path.basename(item.getURI())}"

    atom.workspace.observeActivePaneItem (item) =>
      if item instanceof TextEditor and item.getURI()
        handlePaneItemChanged item

  observeOnWillDestroyPaneItem: ->
    atom.workspace.onWillDestroyPaneItem ({item}) =>
      if item instanceof TextEditor and item.getURI()
        LastEditor.saveDestroyedEditor item

  needRemember: (oldBufferPosition, newBufferPosition) ->
    # Line number delata exceeds or not.
    Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember

  # Helpers
  #-----------------
  lock:     -> @locked = true
  unLock:   -> @locked = false
  isLocked: -> @locked

  jump: (direction) ->
    # Settings tab is not TextEditor instance.
    return unless editor = @getEditor()
    return unless entry  = @history["get#{direction}"]()

    if direction is 'Prev' and @history.isNewest()
      point = @getPosition()
      URI   = editor.getURI()
      @history.pushToHead editor, point, URI

    @lock()

    {URI, point} = entry
    if editor.getURI() is URI # Same pane.
      # Intentionally disable `autoscroll` to set cursor position middle of
      # screen afterward.
      editor.setCursorBufferPosition point, autoscroll: false
      # Adjust cursor position to middle of screen.
      editor.scrollToCursorPosition()
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
    Flasher ?= require './flasher'
    Flasher.flash() if settings.get('flashOnLand')
    @history.dump direction

  getEditor: ->
    atom.workspace.getActiveTextEditor()

  getPosition: (editor=@getEditor())->
    editor.getCursorBufferPosition()

  dump: ->
    console.log @isLocked()
    @history.dump '', true

  debug: (msg) ->
    return unless settings.get('debug')
    console.log msg
