{CompositeDisposable, Disposable} = require 'atom'
History = null

defaultIgnoreCommands = [
  'cursor-history:next',
  'cursor-history:prev',
  'cursor-history:next-within-editor',
  'cursor-history:prev-within-editor',
  'cursor-history:clear',
]

closestTextEditorHavingURI = (target) ->
  editor = target?.closest?('atom-text-editor')?.getModel?()
  return editor if editor?.getURI()

createLocation = (editor, type) ->
  return {
    type: type
    editor: editor
    point: editor.getCursorBufferPosition()
    URI: editor.getURI()
  }

pointByURI = {}
focusedEditorsByURI = {}

module.exports =
  serialize: ->
    {
      history: @history?.serialize() ? @restoredState.history
    }

  activate: (@restoredState) ->
    @subscriptions = new CompositeDisposable

    jump = (args...) => @getHistory().jump(args...)

    @subscriptions.add atom.commands.add 'atom-text-editor',
      'cursor-history:next': -> jump(@getModel(), 'next')
      'cursor-history:prev': -> jump(@getModel(), 'prev')
      'cursor-history:next-within-editor': -> jump(@getModel(), 'next', withinEditor: true)
      'cursor-history:prev-within-editor': -> jump(@getModel(), 'prev', withinEditor: true)
      'cursor-history:clear': => @history?.clear()
      'cursor-history:toggle-debug': => @toggleDebug()

    @observeMouse()
    @observeCommands()
    @subscriptions.add atom.config.observe 'cursor-history.ignoreCommands', (newValue) =>
      @ignoreCommands = defaultIgnoreCommands.concat(newValue)

  toggleDebug: ->
    newValue = not atom.config.get('cursor-history.debug')
    atom.config.set('cursor-history.debug', newValue)
    console.log 'debug: ', newValue

  deactivate: ->
    clearTimeout(@locationCheckTimeoutID)
    @subscriptions.dispose()
    @history?.destroy()
    [@subscriptions, @history, @locationCheckTimeoutID] = []

  getHistory: ->
    return @history if @history?
    History ?= require('./history')

    if @restoredState?.history
      @history = History.deserialize(createLocation, @restoredState.history)
    else
      @history = new History(createLocation)

  # When mouse clicked, cursor position is updated by atom core using setCursorScreenPosition()
  # To track cursor position change caused by mouse click, I use mousedown event.
  #  - Event capture phase: Cursor position is not yet changed.
  #  - Event bubbling phase: Cursor position updated to clicked position.
  observeMouse: ->
    locationStack = []
    @locationCheckTimeoutID = null

    checkLocationChangeAfter = (location, timeout) =>
      clearTimeout(@locationCheckTimeoutID)
      @locationCheckTimeoutID = setTimeout =>
        @checkLocationChange(location)
      , timeout

    handleCapture = (event) ->
      if editor = closestTextEditorHavingURI(event.target)
        location = createLocation(editor, 'mousedown')
        locationStack.push(location)
        # In case, mousedown event was not **bubbled** up, detect location change
        # by comparing old and new location after 300ms
        # This task is cancelled when mouse event bubbled up to avoid duplicate
        # location check.
        #
        # E.g. hyperclick package open another file by mouseclick, it explicitly
        # call `event.stopPropagation()` to prevent default mouse behavior of Atom.
        # In such case we can't catch mouseclick event at bublling phase.
        checkLocationChangeAfter(location, 300)

    handleBubble = (event) =>
      clearTimeout(@locationCheckTimeoutID)
      if location = locationStack.pop()
        setTimeout =>
          @checkLocationChange(location)
        , 100

    workspaceElement = atom.views.getView(atom.workspace)
    workspaceElement.addEventListener('mousedown', handleCapture, true)
    workspaceElement.addEventListener('mousedown', handleBubble, false)

    @subscriptions.add new Disposable ->
      workspaceElement.removeEventListener('mousedown', handleCapture, true)
      workspaceElement.removeEventListener('mousedown', handleBubble, false)

  observeCommands: ->
    isInterestingCommand = (type) =>
      (':' in type) and (type not in @ignoreCommands)

    @locationStackForTestSpec = locationStack = []

    trackLocationTimeout = null
    resetTrackingDelay = ->
      clearTimeout(trackLocationTimeout)
      trackLocationTimeout = null

    trackLocationChangeEdgeDebounced = (type, editor) ->
      if trackLocationTimeout?
        resetTrackingDelay()
      else
        locationStack.push(createLocation(editor, type))
      trackLocationTimeout = setTimeout(resetTrackingDelay, 100)

    @subscriptions.add atom.commands.onWillDispatch ({type, target}) ->
      return unless isInterestingCommand(type)
      if editor = closestTextEditorHavingURI(target)
        trackLocationChangeEdgeDebounced(type, editor)

    @subscriptions.add atom.commands.onDidDispatch ({type, target}) =>
      return if locationStack.length is 0
      return unless isInterestingCommand(type)
      if closestTextEditorHavingURI(target)?
        setTimeout =>
          # To wait cursor position is set on final destination in most case.
          @checkLocationChange(locationStack.pop())
        , 100

  checkLocationChange: (oldLocation) ->
    return unless oldLocation?
    editor = atom.workspace.getActiveTextEditor()
    return unless editor

    if editor.element.hasFocus() and (editor.getURI() is oldLocation.URI)
      # Move within same buffer.
      newLocation = createLocation(editor, oldLocation.type)
      oldPoint = oldLocation.point
      newPoint = newLocation.point

      if oldPoint.isGreaterThan(newPoint)
        {row, column} = oldPoint.traversalFrom(newPoint)
      else
        {row, column} = newPoint.traversalFrom(oldPoint)

      if (row > atom.config.get('cursor-history.rowDeltaToRemember')) or
          (row is 0 and column > atom.config.get('cursor-history.columnDeltaToRemember'))
        @getHistory().add(oldLocation, subject: "Cursor moved")
    else
      @getHistory().add(oldLocation, subject: "Save on focus lost")
