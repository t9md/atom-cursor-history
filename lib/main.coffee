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

getEditor =  ->
  atom.workspace.getActiveTextEditor()

findEditorForPaneByURI = (pane, URI) ->
  for item in pane.getItems() when isTextEditor(item)
    return item if item.getURI() is URI

class Location
  constructor: (@type, @editor) ->
    @point = @editor.getCursorBufferPosition()
    @URI = @editor.getURI()

module.exports =
  config: settings.config
  history: null
  subscriptions: null
  ignoreCommands: null

  onDidChangeLocation: (fn) ->
    @emitter.on('did-change-location', fn)

  activate: ->
    @subscriptions = new CompositeDisposable
    @history = new History
    @emitter = new Emitter

    @subscriptions.add atom.commands.add 'atom-workspace',
      'cursor-history:next': => @jump('next')
      'cursor-history:prev': => @jump('prev')
      'cursor-history:next-within-editor': => @jump('next', withinEditor: true)
      'cursor-history:prev-within-editor': => @jump('prev', withinEditor: true)
      'cursor-history:clear': => @history.clear()
      'cursor-history:toggle-debug': -> settings.toggle 'debug', log: true

    @observeMouse()
    @observeCommands()

    settings.observe 'keepSingleEntryPerBuffer', (newValue) =>
      if newValue
        @history.uniqueByBuffer()

    settings.observe 'ignoreCommands', (newValue) =>
      @ignoreCommands = defaultIgnoreCommands.concat(newValue)

    @onDidChangeLocation ({oldLocation, newLocation}) =>
      if @needToRemember(oldLocation.point, newLocation.point)
        @saveHistory(oldLocation, subject: "Cursor moved")

  deactivate: ->
    settings.destroy()
    @subscriptions.dispose()
    @history.destroy()
    {@history, @subscriptions} = {}

  needToRemember: (oldPoint, newPoint) ->
    if oldPoint.row is newPoint.row
      Math.abs(oldPoint.column - newPoint.column) > settings.get('columnDeltaToRemember')
    else
      Math.abs(oldPoint.row - newPoint.row) > settings.get('rowDeltaToRemember')

  saveHistory: (location, {subject, setToHead}={}) ->
    @history.add(location, {setToHead})
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
    stack = []
    handleCapture = ({target}) ->
      model = target.getModel?()
      return unless model?.getURI?()
      stack.push(new Location('mousedown', model))

    handleBubble = ({target}) =>
      return unless target.getModel?()?.getURI?()?
      setTimeout =>
        @checkLocationChange(stack.pop())
      , 100

    workspaceElement = atom.views.getView(atom.workspace)
    workspaceElement.addEventListener('mousedown', handleCapture, true)
    workspaceElement.addEventListener('mousedown', handleBubble, false)

    @subscriptions.add new Disposable ->
      workspaceElement.removeEventListener('mousedown', handleCapture, true)
      workspaceElement.removeEventListener('mousedown', handleBubble, false)

  isInterestingCommand: (command) ->
    command not in @ignoreCommands

  observeCommands: ->
    shouldSaveLocation = (type, target) ->
      (':' in type) and target.getModel?()?.getURI?()?

    @locationStackForTestSpec = stack = []
    saveLocation = (type, target) ->
      if shouldSaveLocation(type, target)
        stack.push(new Location(type, target.getModel()))

    saveLocationDebounced = _.debounce(saveLocation, 100, true)

    @subscriptions.add atom.commands.onWillDispatch ({type, target}) =>
      if @isInterestingCommand(type)
        saveLocationDebounced(type, target)

    @subscriptions.add atom.commands.onDidDispatch ({type, target}) =>
      return unless @isInterestingCommand(type)
      return if stack.length is 0
      return unless shouldSaveLocation(type, target)
      # console.log  "DidDispatch: #{type}"
      setTimeout =>
        @checkLocationChange(stack.pop())
      , 100

  checkLocationChange: (oldLocation) ->
    return unless oldLocation?
    return unless editor = getEditor()
    if editor.element.hasFocus() and (editor.getURI() is oldLocation.URI)
      # move within same file.
      newLocation = new Location(oldLocation.type, editor)
      @emitter.emit('did-change-location', {oldLocation, newLocation})
    else
      @saveHistory(oldLocation, subject: "Save on focus lost")

  jump: (direction, {withinEditor}={}) ->
    return unless editor = getEditor()
    wasAtHead = @history.isAtHead()
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
      @saveHistory(location, setToHead: false, subject: "Save head position")
      needToLog = false

    land = (editor) =>
      @land(editor, {point, direction, needToLog})

    activePane = atom.workspace.getActivePane()
    if editor.getURI() is URI
      land(editor)
    else if item = findEditorForPaneByURI(activePane, URI)
      activePane.activateItem(item)
      land(item)
    else
      atom.workspace.open(URI, searchAllPanes: settings.get('searchAllPanes')).then(land)

  land: (editor, {point, direction, needToLog}) ->
    originalRow = editor.getCursorBufferPosition().row

    editor.setCursorBufferPosition(point, autoscroll: false)
    editor.scrollToCursorPosition(center: true)

    if settings.get('flashOnLand') and (originalRow isnt point.row)
      @flash(editor)

    if settings.get('debug') and needToLog
      @logHistory(direction)

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
