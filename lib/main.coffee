{CompositeDisposable, TextEditor, Emitter} = require 'atom'
_ = require 'underscore-plus'
path = require 'path'

History  = require './history'
Flasher  = require './flasher'
settings = require './settings'
{delay, debug, reportLocation} = require './utils'

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
      'cursor-history:clear': => @history.clear()
      'cursor-history:toggle-debug': -> settings.toggle 'debug', log: true

    locationStack = []
    getLocation = (type, editor) ->
      point = editor.getCursorBufferPosition()
      URI   = editor.getURI()
      {editor, point, URI, type}

    shouldSaveLocation = ({type, target}) ->
      if (':' in type) and (editor = target.getModel?()) and editor.getURI?()
        true
      else
        false

    ignoreCommands = ['cursor-history:next', 'cursor-history:prev']
    @subscriptions.add atom.commands.onWillDispatch (event) ->
      {type, target} = event
      return if type in ignoreCommands
      return unless shouldSaveLocation(event)
      # debug "WillDispatch: #{type}"
      locationStack.push getLocation(type, target.getModel())

    @subscriptions.add atom.commands.onDidDispatch (event) =>
      {type, target} = event
      return if type in ignoreCommands
      return unless shouldSaveLocation(event)
      # debug "DidDispatch: #{type}"
      # console.log "stackLen #{locationStack.length}"
      delay 300, do (oldLocation = locationStack.pop()) =>
        =>
          if target.hasFocus()
            newLocation = getLocation(type, target.getModel())
            @emitter.emit 'did-change-location', {type, oldLocation, newLocation}
          else
            unless oldLocation
              console.log "WHY!!!!! #{type}"
              # console.log reportLocation(getLocation(type, target.getModel()))
            @saveHistory(oldLocation, dumpMessage: 'save on focusLost')
          # console.log "finished stackLen #{locationStack.length}"

    @subscriptions.add @observeTextEditors()

    @subscriptions.add @onDidChangeLocation ({type, oldLocation, newLocation}) =>
      # debug "old #{reportLocation(oldLocation)}"
      # debug "new #{reportLocation(newLocation)}"
      {point: oldPoint, URI: oldURI} = oldLocation
      {point: newPoint, URI: newURI} = newLocation
      switch
        when oldURI isnt newURI
          @saveHistory oldLocation
        when oldPoint.row is newPoint.row
          return
        else
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

  jump: (direction) ->
    return unless editor = atom.workspace.getActiveTextEditor()
    return unless entry  = @history.get(direction)

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
