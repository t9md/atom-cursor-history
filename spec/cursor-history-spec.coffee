_ = require 'underscore-plus'
{Point} = require 'atom'

sampleFile1 = "sample-1.coffee"
sampleFile2 = "sample-2.coffee"

getEditor = ->
  atom.workspace.getActiveTextEditor()

dispatchCommand = (element, command) ->
  atom.commands.dispatch(element, command)
  advanceClock(100)

isEqualEntry = (e1, e2) ->
  e1Point = Point.fromObject(e1.point)
  e2Point = Point.fromObject(e2.point)
  (e1.URI is e2.URI) and e1Point.isEqual(e2Point)

registerCommands = (element) ->
  atom.commands.add element,
    'test:move-down-2': -> getEditor().moveDown(2)
    'test:move-down-5': -> getEditor().moveDown(5)
    'test:move-up-2':   -> getEditor().moveUp(2)
    'test:move-up-5':   -> getEditor().moveUp(5)

describe "cursor-history", ->
  [editor, editorElement, main, pathSample1] = []
  beforeEach ->
    spyOn(_._, "now").andCallFake -> window.now

    waitsForPromise ->
      atom.packages.activatePackage('cursor-history').then (pack) ->
        main = pack.mainModule

      pathSample1 = atom.project.resolvePath(sampleFile1)

      atom.workspace.open(pathSample1).then (e) ->
        editor = e
        editorElement = atom.views.getView(e)
        jasmine.attachToDOM(editorElement)
        editorElement.focus()
        registerCommands editorElement

      # atom.config.set('cursor-history.debug', true)

  describe "initial state of history entries", ->
    it "is empty", ->
      expect(main.history.entries.length).toBe 0
    it "index is 0", ->
      expect(main.history.index).toBe 0

  describe "history saving", ->
    describe "cursor moved", ->
      it "save history when cursor moved over 4 line by default", ->
        editor.setCursorBufferPosition([0, 5])
        dispatchCommand(editorElement, 'test:move-down-5')
        expect(main.history.entries.length).toBe 1
        {point, URI} = main.history.entries[0]
        expect(point).toEqual([0, 5])
        expect(URI).toEqual(pathSample1)

      it "can save multiple entry", ->
        dispatchCommand(editorElement, 'test:move-down-5')
        dispatchCommand(editorElement, 'test:move-down-5')
        dispatchCommand(editorElement, 'test:move-down-5')
        entries = main.history.entries

        expect(entries.length).toBe 3
        [e1, e2, e3] = entries
        expect(isEqualEntry(e1, {point: [0, 0], URI: pathSample1})).toBe true
        expect(isEqualEntry(e2, {point: [5, 0], URI: pathSample1})).toBe true
        expect(isEqualEntry(e3, {point: [10, 0], URI: pathSample1})).toBe true

      it "wont save history if line delta of move is less than 4 line", ->
        dispatchCommand(editorElement, 'core:move-down')
        expect(editor.getCursorBufferPosition()).toEqual([1, 0])
        expect(main.history.entries.length).toBe 0

    xit "save history when focus lost", ->
    xit "save history when mouseclick", ->
    describe "rowDeltaToRemember settings", ->
      beforeEach ->
        atom.config.set('cursor-history.rowDeltaToRemember', 1)

      describe "when set to 1", ->
        it "save history when cursor move over 1 line", ->
          editor.setCursorBufferPosition([0, 5])
          dispatchCommand(editorElement, 'test:move-down-2')
          expect(editor.getCursorBufferPosition()).toEqual([2, 5])
          expect(main.history.entries.length).toBe 1
          entry = main.history.entries[0]
          expect(isEqualEntry(entry, {point: [0, 5], URI: pathSample1})).toBe true

          dispatchCommand(editorElement, 'test:move-down-2')
          expect(editor.getCursorBufferPosition()).toEqual([4, 5])
          expect(main.history.entries.length).toBe 2
          entry = _.last(main.history.entries)
          expect(isEqualEntry(entry, {point: [2, 5], URI: pathSample1})).toBe true

  describe "go/back history with next/prev commands", ->
    beforeEach ->
      expect(main.history.entries.length).toBe 0
      expect(editor.getCursorBufferPosition()).toEqual([0, 0])

    describe "when history is empty", ->
      it "do nothing with next", ->
        dispatchCommand(editorElement, 'cursor-history:next')
        expect(editor.getCursorBufferPosition()).toEqual([0, 0])
      it "do nothing with prev", ->
        dispatchCommand(editorElement, 'cursor-history:prev')
        expect(editor.getCursorBufferPosition()).toEqual([0, 0])
      it "do nothing with next-within-editor", ->
        dispatchCommand(editorElement, 'cursor-history:next-within-editor')
        expect(editor.getCursorBufferPosition()).toEqual([0, 0])
      it "do nothing with prev-within-editor", ->
        dispatchCommand(editorElement, 'cursor-history:prev-within-editor')
        expect(editor.getCursorBufferPosition()).toEqual([0, 0])

    describe "when history is not empty", ->
      [e1, e2, e3, e4, editor2, editorElement2, workspaceElement, pathSample2] = []
      beforeEach ->
        runs ->
          workspaceElement = atom.views.getView(atom.workspace)
          dispatchCommand(editorElement, 'test:move-down-5')
          dispatchCommand(editorElement, 'test:move-down-5')

        waitsForPromise ->
          pathSample2 = atom.project.resolvePath(sampleFile2)
          atom.workspace.open(pathSample2).then (e) ->
            editor2 = e
            editorElement2 = atom.views.getView(e)
            jasmine.attachToDOM(editorElement2)
            registerCommands(editorElement2)

        runs ->
          dispatchCommand(editorElement2, 'test:move-down-5')
          dispatchCommand(editorElement2, 'test:move-down-5')
          entries = main.history.entries
          expect(entries.length).toBe 4
          expect(main.history.index).toBe 4
          [e1, e2, e3, e4] = entries
          expect(getEditor().getURI()).toBe(pathSample2)
          expect(getEditor().getCursorBufferPosition()).toEqual([10, 0])

      describe "cursor-history:prev", ->
        fit "visit prev entry of cursor history", ->
          atom.commands.dispatch(workspaceElement, 'cursor-history:prev')
          expect(main.history.index).toBe 3
          expect(getEditor().getCursorBufferPosition()).toEqual(e4.point)
          expect(getEditor().getURI()).toBe(pathSample2)

          atom.commands.dispatch(workspaceElement, 'cursor-history:prev')
          expect(main.history.index).toBe 2
          expect(getEditor().getCursorBufferPosition()).toEqual(e3.point)
          expect(getEditor().getURI()).toBe(pathSample2)

          atom.commands.dispatch(workspaceElement, 'cursor-history:prev')
          atom.commands.dispatch(workspaceElement, 'cursor-history:prev')
          # console.log editorElement.hasFocus()
          console.log editorElement2.hasFocus()
          expect(main.history.index).toBe 1
          # console.log editor.getURI()
          # expect(getEditor().getCursorBufferPosition()).toEqual(e2.point)
          # expect(getEditor().getURI()).toBe(pathSample1)

          # atom.commands.dispatch(workspaceElement, 'cursor-history:prev')
          # expect(main.history.index).toBe 1
          # expect(editor.getCursorBufferPosition()).toEqual(e2.point)
          #
          # atom.commands.dispatch(workspaceElement, 'cursor-history:prev')
          # expect(main.history.index).toBe 0
          # expect(editor.getCursorBufferPosition()).toEqual(e1.point)

      describe "cursor-history:next", ->
        it "visit next entry of cursor history", ->
          editor.setCursorBufferPosition(e1.point)
          expect(editor.getCursorBufferPosition()).toEqual(e1.point)
          main.history.index = 0

          atom.commands.dispatch(workspaceElement, 'cursor-history:next')
          expect(main.history.index).toBe 1
          expect(editor.getCursorBufferPosition()).toEqual(e2.point)

          atom.commands.dispatch(workspaceElement, 'cursor-history:next')
          expect(main.history.index).toBe 2
          expect(editor.getCursorBufferPosition()).toEqual(e3.point)

#     describe "cursor-history:next-within-editor", ->
#       it "skip editor with diferent URI(=path)", ->
#     describe "cursor-history:prev-within-editor", ->
#       it "skip editor with diferent URI(=path)", ->
#
#   describe "for destroyed editor", ->
#     describe "excludeClosedBuffer setting", ->
#       atom.config.set('cursor-history.excludeClosedBuffer', true)
#
#     describe "ignoreCommands setting", ->
#       atom.config.set('cursor-history.ignoreCommands', [])
#
