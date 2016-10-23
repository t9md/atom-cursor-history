{CompositeDisposable, Disposable, Emitter, Range} = require 'atom'
_ = require 'underscore-plus'
path = require 'path'

History = require './history'
settings = require './settings'

defaultIgnoreCommands = [
  'cursor-history:next',
  'cursor-history:prev',
  'cursor-history:next-within-editor',
  'cursor-history:prev-within-editor',
  'cursor-history:clear',
]

isTextEditor = (object) ->
  atom.workspace.isTextEditor(object)

findEditorForPaneByURI = (pane, URI) ->
  for item in pane.getItems() when isTextEditor(item)
    return item if item.getURI() is URI

pointDelta = (pointA, pointB) ->
  if pointA.isGreaterThan(pointB)
    pointA.traversalFrom(pointB)
  else
    pointB.traversalFrom(pointA)

class Location
  constructor: (@type, @editor) ->
    @point = @editor.getCursorBufferPosition()
    @URI = @editor.getURI()

module.exports =
  config: settings.config
  history: null
  subscriptions: null
  ignoreCommands: null

  onDidChangeLocation: (fn) -> @emitter.on('did-change-location', fn)
  onDidUnfocus: (fn) -> @emitter.on('did-unfocus', fn)

  activate: ->
    @subscriptions = new CompositeDisposable
    @history = new History
    @emitter = new Emitter

    @subscriptions.add atom.commands.add 'atom-text-editor',
      'cursor-history:next': ({target}) => @jump(target, 'next')
      'cursor-history:prev': ({target}) => @jump(target, 'prev')
      'cursor-history:next-within-editor': ({target}) => @jump(target, 'next', withinEditor: true)
      'cursor-history:prev-within-editor': ({target}) => @jump(target, 'prev', withinEditor: true)
      'cursor-history:clear': => @history.clear()
      'cursor-history:toggle-debug': -> settings.toggle 'debug', log: true

    @observeMouse()
    @observeCommands()
    @observeSettings()

    @onDidChangeLocation ({oldLocation, newLocation}) =>
      {row, column} = pointDelta(oldLocation.point, newLocation.point)
      if (row > settings.get('rowDeltaToRemember')) or (row is 0 and column > settings.get('columnDeltaToRemember'))
        @saveHistory(oldLocation, subject: "Cursor moved")

    @onDidUnfocus ({oldLocation}) =>
      @saveHistory(oldLocation, subject: "Save on focus lost")

  deactivate: ->
    settings.destroy()
    @subscriptions.dispose()
    @history.destroy()
    {@history, @subscriptions} = {}

  observeSettings: ->
    settings.observe 'keepSingleEntryPerBuffer', (newValue) =>
      if newValue
        @history.uniqueByBuffer()

    settings.observe 'ignoreCommands', (newValue) =>
      @ignoreCommands = defaultIgnoreCommands.concat(newValue)

  saveHistory: (location, {subject, setIndexToHead}={}) ->
    @history.add(location, {setIndexToHead})
    @logHistory("#{subject} [#{location.type}]") if settings.get('debug')

  # Mouse handling is not primal purpose of this package
  # I dont' use mouse basically while coding.
  # So to keep codebase minimal and simple,
  #  I don't use editor::onDidChangeCursorPosition() to track cursor position change
  #  caused by mouse click.
  #
  # When mouse clicked, cursor position is updated by atom core using setCursorScreenPosition()
  # To track cursor position change caused by mouse click, I use mousedown event.
  #  - Event capture phase: Cursor position is not yet changed.
  #  - Event bubbling phase: Cursor position updated to clicked position.
  observeMouse: ->
    locationStack = []
    handleCapture = ({target}) ->
      model = target.getModel?()
      if model?.getURI?()
        locationStack.push(new Location('mousedown', model))

    handleBubble = ({target}) =>
      return unless target.getModel?()?.getURI?()?
      setTimeout =>
        @checkLocationChange(location) if location = locationStack.pop()
      , 100

    workspaceElement = atom.views.getView(atom.workspace)
    workspaceElement.addEventListener('mousedown', handleCapture, true)
    workspaceElement.addEventListener('mousedown', handleBubble, false)

    @subscriptions.add new Disposable ->
      workspaceElement.removeEventListener('mousedown', handleCapture, true)
      workspaceElement.removeEventListener('mousedown', handleBubble, false)

  observeCommands: ->
    shouldTackLocation = (type, target) =>
      (':' in type) and (type not in @ignoreCommands) and target.getModel?()?.getURI?()?

    @locationStackForTestSpec = locationStack = []
    trackLocationChange = (type, target) ->
      locationStack.push(new Location(type, target.getModel()))
    trackLocationChangeDebounced = _.debounce(trackLocationChange, 100, true)

    @subscriptions.add atom.commands.onWillDispatch ({type, target}) ->
      if shouldTackLocation(type, target)
        trackLocationChangeDebounced(type, target)

    @subscriptions.add atom.commands.onDidDispatch ({type, target}) =>
      return if locationStack.length is 0
      if shouldTackLocation(type, target)
        setTimeout =>
          # To wait cursor position is set on final destination in most case.
          @checkLocationChange(location) if location = locationStack.pop()
        , 100

  checkLocationChange: (oldLocation) ->
    editor = atom.workspace.getActiveTextEditor()
    return unless editor

    if editor.element.hasFocus() and (editor.getURI() is oldLocation.URI)
      # Move within same buffer.
      newLocation = new Location(oldLocation.type, editor)
      @emitter.emit('did-change-location', {oldLocation, newLocation})
    else
      @emitter.emit('did-unfocus', {oldLocation})

  jump: (editorElement, direction, {withinEditor}={}) ->
    editor = editorElement.getModel()
    wasAtHead = @history.isIndexAtHead()
    if withinEditor
      entry = @history.get(direction, URI: editor.getURI())
    else
      entry = @history.get(direction)

    return unless entry?
    # FIXME, Explicitly preserve point, URI by setting independent value,
    # since its might be set null if entry.isAtSameRow()
    {point, URI} = entry

    needToLog = true
    if (direction is 'prev') and wasAtHead
      location = new Location('prev', editor)
      @saveHistory(location, setIndexToHead: false, subject: "Save head position")
      needToLog = false

    land = (editor) =>
      @land(editor, point)
      if settings.get('debug') and needToLog
        @logHistory(direction)

    activePane = atom.workspace.getActivePane()
    if editor.getURI() is URI
      land(editor)
    else if item = findEditorForPaneByURI(activePane, URI)
      activePane.activateItem(item)
      land(item)
    else
      atom.workspace.open(URI, searchAllPanes: settings.get('searchAllPanes')).then(land)

  land: (editor, point) ->
    originalRow = editor.getCursorBufferPosition().row

    editor.setCursorBufferPosition(point, autoscroll: false)
    editor.scrollToCursorPosition(center: true)

    if settings.get('flashOnLand') and (originalRow isnt point.row)
      @flash(editor)

  flashMarker: null
  flash: (editor) ->
    @flashMarker?.destroy()

    cursor = editor.getLastCursor()
    switch settings.get('flashType')
      when 'line'
        type = 'line'
        range = cursor.getCurrentLineBufferRange()
      when 'word'
        type = 'highlight'
        range = cursor.getCurrentWordBufferRange()
      when 'point'
        type = 'highlight'
        range = editor.bufferRangeForScreenRange(cursor.getScreenRange())

    @flashMarker = editor.markBufferRange(range)
    className = "cursor-history-#{settings.get('flashColor')}"
    editor.decorateMarker(@flashMarker, {type, class: className})

    setTimeout =>
      @flashMarker?.destroy()
    , settings.get('flashDurationMilliSeconds')

  logHistory: (msg) ->
    s = """
    # cursor-history: #{msg}
    #{@history.inspect()}
    """
    console.log s, "\n\n"
