{CompositeDisposable, Disposable} = require 'atom'

defaultIgnoreCommands = [
  'cursor-history:next',
  'cursor-history:prev',
  'cursor-history:next-within-editor',
  'cursor-history:prev-within-editor',
  'cursor-history:clear',
]

closestTextEditorHavingURI = (target) ->
  editor = target?.closest?('atom-text-editor')?.getModel()
  return editor if editor?.getURI()

createLocation = (editor, type) ->
  return {
    type: type
    editor: editor
    point: editor.getCursorBufferPosition()
    URI: editor.getURI()
  }

module.exports =
  activate: ->
    @subscriptions = new CompositeDisposable

    jump = (args...) => @history?.jump(args...)

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
    @subscriptions.dispose()
    @history?.destroy()
    [@subscriptions, @history] = []

  getHistory: ->
    @history ?= new (require('./history'))(createLocation)

  # When mouse clicked, cursor position is updated by atom core using setCursorScreenPosition()
  # To track cursor position change caused by mouse click, I use mousedown event.
  #  - Event capture phase: Cursor position is not yet changed.
  #  - Event bubbling phase: Cursor position updated to clicked position.
  observeMouse: ->
    locationStack = []
    handleCapture = (event) ->
      if editor = closestTextEditorHavingURI(event.target)
        locationStack.push(createLocation(editor, 'mousedown'))

    handleBubble = (event) =>
      if editor = closestTextEditorHavingURI(event.target)
        setTimeout =>
          @checkLocationChange(locationStack.pop())
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
