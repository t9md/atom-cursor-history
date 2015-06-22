{CompositeDisposable, TextEditor} = require 'atom'
path = require 'path'
_ = require 'underscore-plus'

History    = null
LastEditor = null
Flasher    = null
settings   = require './settings'

module.exports =
  config: settings.config
  history: null
  subscriptions: null
  editorSubscriptions: null
  lastEditor: null
  locked: false

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
    # @subscriptions.add @extendSymbolsView()

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

    atom.packages.onDidActivatePackage (pack) ->
      return unless pack.name is 'symbols-view'
      console.log "CALLED"
      main = pack.mainModule

      @openTags['FileView']    = extendOpenTag main.createFileView()
      @openTags['ProjectView'] = extendOpenTag main.createProjectView()
      @openTags['GoToView']    = extendOpenTag main.createGoToView()
      @openTags['GoBackView']  = extendOpenTag main.createGoBackView()

      # fileView = main.createProjectView()
      # fileView = main.createGoToView()

      # fileView.openTag = (params...) ->
      #   console.log "Before"
      #   console.log @stack
      #   console.log @constructor.name
      #   openTag params...
      #   console.log "After"
      #
      console.log result
      # libPath = path.join(atom.packages.resolvePackagePath('symbols-view') , 'lib', 'symbols-view')
      # SymbolsView = require libPath
      # _openTag = SymbolsView::openTag
      # SymbolsView::openTag = (params...) ->
      #   # if @constructor
      #   # setTimeout =>
      #   #   console.log "before", @panel.isVisible()
      #   # , 300
      #   console.log "Before"
      #   console.log @stack
      #   console.log @constructor.name
      #   _openTag.call(this, params...)
      #   console.log "After"
      #   console.log @stack
      #   # setTimeout =>
      #   #   console.log "after", @panel.isVisible()
      #   # , 300

  symbolsViewHandlers:
    FileView: (panel) ->
      @withPanel panel,
        # At the timing symbol-views panel show, first item in symobls
        # already selected(this mean cursor position have changed).
        # So we can't use TexitEditor::getCursorBufferPosition(), fotunately,
        # FileView serialize buffer state initaially, we use this.
        onShow: =>
          console.log "Shown FileView"
          editor = @getEditor()
          point  = panel.getItem().initialState?.bufferRanges[0].start
          {editor, point}
        onHide: =>
          console.log "Hidden FileView"
          editor = @getEditor()
          point  = editor.getCursorBufferPosition()
          {editor, point}

    ProjectView: (panel) ->
      @withPanel panel,
        onShow: =>
          console.log "Shown ProjectView"
          editor = @getEditor()
          point  = editor.getCursorBufferPosition()
          {editor, point}
        onHide: =>
          console.log "Hidden ProjectView"
          editor = @getEditor()
          point  = editor.getCursorBufferPosition()
          {editor, point}

  observeModalPanel: ->
    atom.workspace.panelContainers['modal'].onDidAddPanel ({panel, index}) =>
      item = panel.getItem()
      name = item.constructor.name

      # [CAUTION] Simply checking constructor name is not enough
      # e.g. ProjectView is also used in `fuzzy-finder`.
      return unless (name in ['FileView', 'ProjectView']) and
        typeof(item.openTag) is 'function'

      # return unless name in ['GoToView', 'GoBackView', 'FileView', 'ProjectView']
      return unless name in ['FileView', 'ProjectView']
      @symbolsViewHandlers[name]?.bind(this)(panel)

  observeTextEditors: ->
    handleChangePath = (editor) =>
      orgURI = editor.getURI()

      @editorSubscriptions[editor.id].add editor.onDidChangePath =>
        newURI = editor.getURI()
        @history.rename orgURI, newURI
        @lastEditor.rename orgURI, newURI
        orgURI = newURI

    handleCursorMoved = ({oldBufferPosition, newBufferPosition, cursor}) =>
      editor = cursor.editor
      return if editor.hasMultipleCursors()
      return unless URI = editor.getURI()

      if @needRemember(oldBufferPosition, newBufferPosition)
        @history.add editor, oldBufferPosition, URI, dumpMessage: "[Cursor moved] save history"

    atom.workspace.observeTextEditors (editor) =>
      @editorSubscriptions[editor.id] = new CompositeDisposable
      handleChangePath(editor)

      @editorSubscriptions[editor.id].add editor.onDidChangeCursorPosition (event) =>
        return if @isLocked() # for performance
        return if event.oldBufferPosition.row is event.newBufferPosition.row # for performance.
        setTimeout =>
          # When symbols-view's modal panel shown, we lock() but its delayed.
          # So checking lock state here is important.
          return if @isLocked()
          handleCursorMoved event
        , 300

      @editorSubscriptions[editor.id].add editor.onDidDestroy =>
        @editorSubscriptions[editor.id]?.dispose()
        delete @editorSubscriptions[editor.id]

  observeActivePaneItem: ->
    handlePaneItemChanged = (item) =>
      # We need to track former active pane to know cursor position when active pane was changed.
      @lastEditor ?= new LastEditor(item)

      {editor, point, URI: lastURI} = @lastEditor.getInfo()
      if not @isLocked() and (lastURI isnt item.getURI())
        @history.add editor, point, lastURI, dumpMessage: "[Pane item changed] save history"
      console.log "lock?: #{@isLocked()}: #{@_locker}"

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
    # console.log [oldBufferPosition, newBufferPosition]
    # Line number delata exceeds or not.
    Math.abs(oldBufferPosition.row - newBufferPosition.row) > @rowDeltaToRemember

  # Helpers
  #-----------------
  withPanel: (panel, {onShow, onHide}) ->
    [oldEditor, oldPoint, newEditor, newPoint] = []
    panelSubscription = panel.onDidChangeVisible (visible) =>
      if visible
        @lock panel.getItem().constructor.name
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

  lock: (locker) ->
    @_locker = locker
    @locked = true

  unLock:   -> @locked = false
  isLocked: -> @locked

  jump: (direction) ->
    # Settings tab is not TextEditor instance.
    return unless activeEditor = @getEditor()
    return unless entry = @history["get#{direction}"]()

    if direction is 'Prev' and @history.isNewest()
      point = activeEditor.getCursorBufferPosition()
      URI   = activeEditor.getURI()
      @history.pushToHead activeEditor, point, URI

    @lock "Jump#{direction}"

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
    Flasher ?= require './flasher'
    Flasher.flash() if settings.get('flashOnLand')
    @history.dump direction

  getEditor: ->
    atom.workspace.getActiveTextEditor()

  dump: ->
    console.log @isLocked()
    @history.dump '', true

  debug: (msg) ->
    return unless settings.get('debug')
    console.log msg
