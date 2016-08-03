# Refactoring Status: 90%
{CompositeDisposable, Disposable, Emitter, Range} = require 'atom'
_ = require 'underscore-plus'
path = require 'path'

History = null
settings = require './settings'
flashTimer = null
flashMarker = null

ignoreCommands = [
  'cursor-history:next',
  'cursor-history:prev',
  'cursor-history:next-within-editor',
  'cursor-history:prev-within-editor',
  'cursor-history:clear',
]

module.exports =
  config: settings.config
  history: null
  subscriptions: null

  activate: ->
    @subscriptions = new CompositeDisposable
    History = require './history'
    @history = new History
    @emitter = new Emitter

    @subscriptions.add atom.commands.add 'atom-workspace',
      'cursor-history:next': => @jump('next')
      'cursor-history:prev': => @jump('prev')
      'cursor-history:next-within-editor': => @jump('next', withinEditor: true)
      'cursor-history:prev-within-editor': => @jump('prev', withinEditor: true)
      'cursor-history:clear': => @history.clear()
      'cursor-history:toggle-debug': -> settings.toggle 'debug', log: true

    uniqueByBuffer = (newValue) =>
      @history.uniqueByBuffer() if newValue
    @subscriptions.add(settings.observe('keepSingleEntryPerBuffer', uniqueByBuffer))

    @observeMouse()
    @observeCommands()

    saveHistoryIfNeeded = ({oldLocation, newLocation}) =>
      if @needToRemember(oldLocation.point, newLocation.point)
        @saveHistory(oldLocation, subject: "Cursor moved")
    @onDidChangeLocation(saveHistoryIfNeeded)

  onDidChangeLocation: (fn) ->
    @emitter.on('did-change-location', fn)

  deactivate: ->
    @subscriptions.dispose()
    @history?.destroy()
    {@history, @subscriptions} = {}

  needToRemember: (oldPoint, newPoint) ->
    if oldPoint.row is newPoint.row
      Math.abs(oldPoint.column - newPoint.column) > settings.get('columnDeltaToRemember')
    else
      Math.abs(oldPoint.row - newPoint.row) > settings.get('rowDeltaToRemember')

  saveHistory: (location, {subject, setToHead}={}) ->
    @history.add(location)
    # Only when setToHead is true, we can safely remove @entries.
    @history.removeEntries() if (setToHead ? true)
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
    handleCapture = ({target}) =>
      model = target.getModel?()
      return unless model?.getURI?()
      stack.push(@newLocation('mousedown', model))

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

  isIgnoreCommands: (command) ->
    (command in ignoreCommands) or (command in settings.get('ignoreCommands'))

  observeCommands: ->
    shouldSaveLocation = (type, target) ->
      (':' in type) and target.getModel?()?.getURI?()?

    stack = []
    saveLocation = _.debounce (type, target) =>
      return unless shouldSaveLocation(type, target)
      # console.log  "WillDispatch: #{type}"
      stack.push(@newLocation(type, target.getModel()))
    , 100, true

    @subscriptions.add atom.commands.onWillDispatch ({type, target}) =>
      return if @isIgnoreCommands(type)
      saveLocation(type, target)

    @subscriptions.add atom.commands.onDidDispatch ({type, target}) =>
      return if @isIgnoreCommands(type)
      return if stack.length is 0
      return unless shouldSaveLocation(type, target)
      # console.log  "DidDispatch: #{type}"
      setTimeout =>
        @checkLocationChange(stack.pop())
      , 100

  checkLocationChange: (oldLocation) ->
    return unless oldLocation?
    return unless editor = @getEditor()
    editorElement = atom.views.getView(editor)
    if editorElement.hasFocus() and (editor.getURI() is oldLocation.URI)
      newLocation = @newLocation(oldLocation.type, editor)
      @emitter.emit('did-change-location', {oldLocation, newLocation})
    else
      @saveHistory(oldLocation, subject: "Save on focus lost")

  jump: (direction, {withinEditor}={}) ->
    return unless (editor = @getEditor())?
    wasAtHead = @history.isAtHead()
    entry = do =>
      switch
        when withinEditor
          uri = editor.getURI()
          @history.get(direction, ({URI}) -> URI is uri)
        else
          @history.get(direction, -> true)

    return unless entry?
    # FIXME, Explicitly preserve point, URI by setting independent value,
    # since its might be set null if entry.isAtSameRow()
    {point, URI} = entry

    needToLog = true
    if (direction is 'prev') and wasAtHead
      location = @newLocation('prev', editor)
      @saveHistory(location, setToHead: false, subject: "Save head position")
      needToLog = false

    land = (editor) =>
      @land(editor, {point, direction, needToLog})

    openEditor = ->
      if editor.getURI is URI
        Promise.resolve(editor)
      else
        atom.workspace.open(URI, searchAllPanes: settings.get('searchAllPanes'))

    openEditor().then(land)


  land: (editor, {point, direction, needToLog}) ->
    originalRow = editor.getCursorBufferPosition().row
    editor.setCursorBufferPosition(point)
    editor.scrollToCursorPosition({center: true})

    if settings.get('flashOnLand') and (originalRow isnt point.row)
      @flash(
        flashType: settings.get('flashType')
        className: "cursor-history-#{settings.get('flashColor')}"
        timeout: settings.get('flashDurationMilliSeconds')
      )

    if settings.get('debug') and needToLog
      @logHistory(direction)

  newLocation: (type, editor) ->
    {
      type,
      editor,
      point: editor.getCursorBufferPosition(),
      URI: editor.getURI()
    }

  logHistory: (msg) ->
    s = """
    # cursor-history: #{msg}
    #{@history.inspect()}
    """
    console.log s, "\n\n"

  getEditor: ->
    atom.workspace.getActiveTextEditor()

  flash: ({flashType, className, timeout}) ->
    flashMarker?.destroy()
    clearTimeout(flashTimer)

    editor = @getEditor()
    cursor = editor.getLastCursor()
    switch flashType
      when 'line'
        type = 'line'
        range = cursor.getCurrentLineBufferRange()
      when 'word'
        type = 'highlight'
        range = cursor.getCurrentWordBufferRange()
      when 'point'
        type = 'highlight'
        range = Range.fromPointWithDelta(cursor.getCursorBufferPosition(), 0, 1)

    flashMarker = editor.markBufferRange(range)
    decoration = editor.decorateMarker(flashMarker, {type, class: className})

    clearFlash = ->
      flashMarker.destroy()
      flashTimer = null
    flashTimer = setTimeout(clearFlash, timeout)
