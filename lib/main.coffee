# Refactoring Status: 90%
{CompositeDisposable, Disposable, TextEditor, Emitter} = require 'atom'
_ = require 'underscore-plus'
path = require 'path'

History  = require './history'
Flasher  = require './flasher'
settings = require './settings'
{
  delay,
  debug,
  getLocation
} = require './utils'

module.exports =
  config: settings.config
  history: null
  subscriptions: null

  activate: ->
    @subscriptions = new CompositeDisposable
    @history = new History
    @emitter = new Emitter

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @jump('next')
      'cursor-history:prev':  => @jump('prev')
      'cursor-history:next-within-editor': => @jump('next', true)
      'cursor-history:prev-within-editor': => @jump('prev', true)
      'cursor-history:clear': => @history.clear()
      'cursor-history:toggle-debug': -> settings.toggle 'debug', log: true

    @observeMouse()
    @observeCommands()

    @onDidChangeLocation ({oldLocation, newLocation}) =>
      if @needRemember(oldLocation.point, newLocation.point)
        @saveHistory oldLocation, subject: "Cursor moved"

  needRemember: (oldPoint, newPoint) ->
    Math.abs(oldPoint.row - newPoint.row) > settings.get('rowDeltaToRemember')

  saveHistory: (location, {subject, setIndexToHead}={}) ->
    @history.add location, {setIndexToHead}
    if settings.get('debug')
      @logHistory "#{subject} [#{location.type}]"

  onDidChangeLocation: (fn) ->
    @emitter.on 'did-change-location', fn

  deactivate: ->
    @subscriptions.dispose()
    @subscriptions = null
    @history?.destroy()
    @history = null

  observeMouse: ->
    locationStack = []
    handleCapture = ({target}) =>
      return unless target.getModel?()?.getURI?()?
      return unless editor = atom.workspace.getActiveTextEditor()
      locationStack.push @getLocation('mousedown', editor)

    handleBubble = ({target}) =>
      return unless target.getModel?()?.getURI?()?
      delay 100, =>
        @checkLocationChange(locationStack.pop()) if locationStack.length

    # Mouse handling is not primal purpose of this package
    # I dont' use mouse basically while coding.
    # So keep codebase minimal and simple,
    #  I don't use editor::onDidChangeCursorPosition() to track
    #  cursor position change caused by mouse click.

    # When mouse clicked, cursor position is updated by atom core using setCursorScreenPosition()
    # To track cursor position change caused by mouse click, I use mousedown event.
    #  - Event capture phase: Cursor position is not yet changed.
    #  - Event bubbling phase: Cursor position updated to clicked position.
    workspaceElement = atom.views.getView(atom.workspace)
    workspaceElement.addEventListener 'mousedown', handleCapture, true
    workspaceElement.addEventListener 'mousedown', handleBubble, false

    @subscriptions.add new Disposable ->
      workspaceElement.removeEventListener 'mousedown', handleCapture, true
      workspaceElement.removeEventListener 'mousedown', handleBubble, false

  observeCommands: ->
    ignoreCommands = [
      'cursor-history:next',
      'cursor-history:prev',
      'cursor-history:next-within-editor',
      'cursor-history:prev-within-editor',
      'cursor-history:clear',
    ]
    shouldSaveLocation = (type, target) ->
      (':' in type) and target.getModel?()?.getURI?()?

    locationStack = []
    saveLocation = _.debounce (type, target) =>
      return unless shouldSaveLocation(type, target)
      # debug "WillDispatch: #{type}"
      locationStack.push @getLocation(type, target.getModel())
    , 100, true

    @subscriptions.add atom.commands.onWillDispatch ({type, target}) ->
      return if type in ignoreCommands
      saveLocation(type, target)

    @subscriptions.add atom.commands.onDidDispatch ({type, target}) =>
      return if type in ignoreCommands
      return if locationStack.length is 0
      return unless shouldSaveLocation(type, target)
      # debug "DidDispatch: #{type}"
      delay 100, =>
        @checkLocationChange(locationStack.pop()) if locationStack.length

  checkLocationChange: (oldLocation) ->
    {type, URI} = oldLocation
    return unless editor = atom.workspace.getActiveTextEditor()
    editorElement = atom.views.getView(editor)
    if editorElement.hasFocus() and (editor.getURI() is URI)
      newLocation = @getLocation(type, editor)
      @emitter.emit 'did-change-location', {oldLocation, newLocation}
    else
      @saveHistory oldLocation, subject: "Save on focus lost"

  jump: (direction, withinEditor=false) ->
    return unless editor = atom.workspace.getActiveTextEditor()
    forURI = if withinEditor then editor.getURI() else null
    needToSave = (direction is 'prev') and @history.isIndexAtHead()
    unless entry = @history.get(direction, URI: forURI)
      return
    # FIXME, Explicitly preserve point, URI by setting independent value,
    # since its might be set null if entry.isAtSameRow()
    {point, URI} = entry

    if needToSave
      @saveHistory @getLocation('prev', editor),
        setIndexToHead: false
        subject: "Save head position"

    options = {point, direction, log: not needToSave}
    if editor.getURI() is URI
      @land(editor, options)
    else
      searchAllPanes = settings.get('searchAllPanes')
      atom.workspace.open(URI, {searchAllPanes}).done (editor) =>
        @land(editor, options)

  land: (editor, {point, direction, log}) ->
    editor.scrollToBufferPosition(point, center: true)
    editor.setCursorBufferPosition(point)
    Flasher.flash() if settings.get('flashOnLand')

    if settings.get('debug') and log
      @logHistory(direction)

  getLocation: (type, editor) ->
    point = editor.getCursorBufferPosition()
    URI   = editor.getURI()
    {editor, point, URI, type}

  logHistory: (msg) ->
    s = """
    # cursor-history: #{msg}
    #{@history.inspect()}
    """
    console.log s, "\n\n"
