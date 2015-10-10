{CompositeDisposable, TextEditor, Emitter} = require 'atom'
_ = require 'underscore-plus'
path = require 'path'

History  = require './history'
Flasher  = require './flasher'
settings = require './settings'
{
  delay,
  debug,
  reportLocation
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
    subs.push @observeTextEditors()
    subs.push @observeCommands()
    @subscriptions.add(_.flatten(subs)...)

    @onDidChangeLocation ({type, oldLocation, newLocation}) =>
      {point: oldPoint, URI: oldURI} = oldLocation
      {point: newPoint, URI: newURI} = newLocation
      switch
        when (oldURI isnt newURI)           then @saveHistory(oldLocation)
        when (oldPoint.row is newPoint.row) then return
        else
          console.log [oldPoint.row, newPoint.row]
          if Math.abs(oldPoint.row - newPoint.row) > settings.get('rowDeltaToRemember')
            @saveHistory oldLocation, dumpMessage: "[Cursor moved] save history"

  saveHistory: (location, {dumpMessage}={}) ->
    if dumpMessage?
      location.dumpMessage = dumpMessage
    @history.add location

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
    subs.push atom.commands.onWillDispatch (event) ->
      {type, target} = event
      return unless shouldSaveLocation({type, target})
      debug "WillDispatch: #{type}"
      locationStack.push getLocation(type, target.getModel())

    subs.push atom.commands.onDidDispatch (event) =>
      {type, target} = event
      return unless shouldSaveLocation({type, target})
      debug "DidDispatch: #{type}"
      oldLocation = locationStack.pop()
      if target.hasFocus()
        newLocation = getLocation(type, target.getModel())
        @emitter.emit 'did-change-location', {type, oldLocation, newLocation}
      else
        @saveHistory(oldLocation, dumpMessage: 'save on focusLost')
    subs

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
    if withinEditor
      entry = @history.get(direction, URI: editor.getURI())
    else
      entry = @history.get(direction)

    return unless entry

    if direction is 'prev' and @history.isNewest()
      @history.add
        editor: editor
        point: editor.getCursorBufferPosition()
        URI: editor.getURI()
        setIndexToHead: false

    {URI, point} = entry
    if editor.getURI() is URI # Same pane.
      @landToPoint(editor, point)
      @history.dump direction
    else # Jump to different pane
      options = searchAllPanes: settings.get('searchAllPanes')
      atom.workspace.open(URI, options).done (editor) =>
        @landToPoint(editor, point)
        @history.dump direction

  landToPoint: (editor, point) ->
    editor.scrollToBufferPosition(point, center: true)
    editor.setCursorBufferPosition(point)
    Flasher.flash() if settings.get('flashOnLand')
