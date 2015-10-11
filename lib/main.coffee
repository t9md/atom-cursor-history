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
  editorSubscriptions: null

  activate: ->
    @subscriptions = new CompositeDisposable
    @editorSubscriptions = {}
    @history = new History(settings.get('max'))
    @emitter = new Emitter

    atom.commands.add 'atom-workspace',
      'cursor-history:next':  => @jump('next')
      'cursor-history:prev':  => @jump('prev')
      'cursor-history:next-within-editor': => @jump('next', true)
      'cursor-history:prev-within-editor': => @jump('prev', true)
      'cursor-history:clear': => @history.clear()
      'cursor-history:toggle-debug': -> settings.toggle 'debug', log: true

    subs = []
    subs.push @observeMouse()
    subs.push @observeTextEditors()
    subs.push @observeCommands()

    @subscriptions.add(_.flatten(subs)...)

    @onDidChangeLocation ({type, oldLocation, newLocation}) =>
      {point: oldPoint, URI: oldURI} = oldLocation
      {point: newPoint, URI: newURI} = newLocation
      switch
        when (oldURI isnt newURI)
          @saveHistory(oldLocation, debugTitle: "URI changed")
        when (oldPoint.row is newPoint.row)
          return
        else
          if @needRemember(oldPoint, newPoint)
            @saveHistory oldLocation, debugTitle: "Cursor moved"

  needRemember: (oldPoint, newPoint) ->
    Math.abs(oldPoint.row - newPoint.row) > settings.get('rowDeltaToRemember')

  saveHistory: (location, {debugTitle}={}) ->
    @history.add location
    if settings.get('debug')
      console.log "# cursor-history: #{debugTitle} [#{location.type}]"
      @history.dump()

  onDidChangeLocation: (fn) ->
    @emitter.on 'did-change-location', fn

  deactivate: ->
    for editorID, subs of @editorSubscriptions
      subs.dispose()
    @editorSubscriptions = null
    @subscriptions.dispose()
    @subscriptions = null
    settings.dispose()
    @history?.destroy()
    @history = null

  observeMouse: ->
    locationStack = []
    shouldSaveLocation = (target) ->
      if (editor = target.getModel?()) and editor.getURI?()
        true
      else
        false

    handleCapture = ({target}) ->
      return unless shouldSaveLocation(target)
      activeEditor = atom.workspace.getActiveTextEditor()
      oldLocation = getLocation('mousedown', activeEditor)
      locationStack.push oldLocation

    handleBubble = ({target}) =>
      delay 100, =>
        return unless shouldSaveLocation(target)
        @processLocationChange locationStack.pop()

    # Mouse handling is not primal purpose of this package
    # I dont' use mouse basically while coding.
    # So keep codebase minimal and simple,
    #  I won't use editor::onDidChangeCursorPosition() to track
    #  cursor position change caused by mouse click.

    # When mouse clicked, cursor position is updated by atom core using setCursorScreenPosition()
    # To track cursor position change caused by mouse click, I use mousedown event.
    #  - Event capture phase: Cursor position is not yet changed.
    #  - Event bubbling phase: Cursor position updated to clicked position.
    workspaceElement = atom.views.getView(atom.workspace)
    workspaceElement.addEventListener 'mousedown', handleCapture, true
    workspaceElement.addEventListener 'mousedown', handleBubble, false

    new Disposable ->
      workspaceElement.removeEventListener 'mousedown', handleCapture, true
      workspaceElement.removeEventListener 'mousedown', handleBubble, false

  observeCommands: ->
    ignoreCommands = [
      'cursor-history:next',
      'cursor-history:prev',
      'cursor-history:next-within-editor',
      'cursor-history:prev-within-editor',
    ]
    shouldSaveLocation = ({type, target}) ->
      return false if type in ignoreCommands
      if (':' in type) and (editor = target.getModel?()) and editor.getURI?()
        true
      else
        false

    locationStack = []
    subs = []

    saveLocation = (event) ->
      {type, target} = event
      return unless shouldSaveLocation({type, target})
      # debug "WillDispatch: #{type}"
      locationStack.push getLocation(type, target.getModel())

    subs.push atom.commands.onWillDispatch _.debounce(saveLocation, 200)

    subs.push atom.commands.onDidDispatch (event) =>
      return if locationStack.length is 0
      {type, target} = event
      return unless shouldSaveLocation({type, target})
      @processLocationChange locationStack.pop()
    subs

  processLocationChange: (oldLocation) ->
    {type} = oldLocation
    activeEditor = atom.workspace.getActiveTextEditor()
    editorElement = atom.views.getView(activeEditor)
    if editorElement.hasFocus() and (activeEditor.getURI() is oldLocation.URI)
      newLocation = getLocation(type, activeEditor)
      @emitter.emit 'did-change-location', {type, oldLocation, newLocation}
    else
      @saveHistory(oldLocation, debugTitle: "Save on focus lost")

  observeTextEditors: ->
    atom.workspace.observeTextEditors (editor) =>
      return unless editor.getURI()
      @editorSubscriptions[editor.id] = subs = new CompositeDisposable

      subs.add editor.onDidChangePath do (editor) =>
        oldURI = editor.getURI()
        =>
          newURI = editor.getURI()
          @history.rename oldURI, newURI
          oldURI = newURI

      subs.add editor.onDidDestroy =>
        subs.dispose()
        delete @editorSubscriptions[editor.id]

  jump: (direction, withinEditor=false) ->
    return unless editor = atom.workspace.getActiveTextEditor()
    entry =
      if withinEditor
        @history.get(direction, URI: editor.getURI())
      else
        @history.get(direction)
    return unless entry

    savedHistory = false
    if direction is 'prev' and @history.isNewest()
      location =
        type: 'prev'
        editor: editor
        point: editor.getCursorBufferPosition()
        URI: editor.getURI()
        setIndexToHead: false
      @saveHistory(location, debugTitle: "Save head position")
      savedHistory = true

    {URI, point} = entry
    if editor.getURI() is URI # Same pane.
      @landToPoint(editor, point)
      if settings.get('debug') and not savedHistory
        console.log "# cursor-history: #{direction}"
        @history.dump()

    else # Jump to different pane
      options = searchAllPanes: settings.get('searchAllPanes')
      atom.workspace.open(URI, options).done (editor) =>
        @landToPoint(editor, point)
        @history.dump direction

  landToPoint: (editor, point) ->
    editor.scrollToBufferPosition(point, center: true)
    editor.setCursorBufferPosition(point)
    Flasher.flash() if settings.get('flashOnLand')
