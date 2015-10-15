_ = require 'underscore-plus'
{Point} = require 'atom'

sampleFile1 = "sample-1.coffee"
sampleFile2 = "sample-2.coffee"

getEditor = ->
  atom.workspace.getActiveTextEditor()

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

dispatchCommand = (element, command) ->
  atom.commands.dispatch(element, command)
  advanceClock(100)

describe "cursor-history", ->
  [editor, editorElement, main, pathSample1, pathSample2, workspaceElement] = []

  beforeEach ->
    spyOn(_._, "now").andCallFake -> window.now

    pathSample1 = atom.project.resolvePath(sampleFile1)
    pathSample2 = atom.project.resolvePath(sampleFile2)

    workspaceElement = atom.views.getView(atom.workspace)
    jasmine.attachToDOM(workspaceElement)

    waitsForPromise ->
      atom.packages.activatePackage('cursor-history').then (pack) ->
        main = pack.mainModule

    waitsForPromise ->
      atom.workspace.open(pathSample1).then (e) ->
        editor = e
        editorElement = atom.views.getView(e)
        registerCommands(editorElement)

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
    isInitialState = ->
      expect(main.history.entries.length).toBe 0
      expect(editor.getCursorBufferPosition()).toEqual([0, 0])

    beforeEach ->
      isInitialState()

    describe "when history is empty", ->
      it "do nothing with next", ->
        dispatchCommand(editorElement, 'cursor-history:next')
        isInitialState()
      it "do nothing with prev", ->
        dispatchCommand(editorElement, 'cursor-history:prev')
        isInitialState()
      it "do nothing with next-within-editor", ->
        dispatchCommand(editorElement, 'cursor-history:next-within-editor')
        isInitialState()
      it "do nothing with prev-within-editor", ->
        dispatchCommand(editorElement, 'cursor-history:prev-within-editor')
        isInitialState()

    describe "when history is not empty", ->
      [e0, e1, e2, e3, editor2, editorElement2] = []
      beforeEach ->
        runs ->
          dispatchCommand(editorElement, 'test:move-down-5')
          dispatchCommand(editorElement, 'test:move-down-5')

        waitsForPromise ->
          atom.workspace.open(pathSample2).then (e) ->
            editor2 = e
            editorElement2 = atom.views.getView(e)
            registerCommands(editorElement2)

        runs ->
          dispatchCommand(editorElement2, 'test:move-down-5')
          dispatchCommand(editorElement2, 'test:move-down-5')
          entries = main.history.entries
          expect(entries.length).toBe 4
          expect(main.history.index).toBe 4
          [e0, e1, e2, e3] = entries
          expect(getEditor().getURI()).toBe(pathSample2)
          expect(getEditor().getCursorBufferPosition()).toEqual([10, 0])

      runCommand = (command, fn) ->
        runs ->
          spyOn(main, "land").andCallThrough()
          atom.commands.dispatch(workspaceElement, command)

        waitsFor -> main.land.callCount is 1
        runs -> fn()
        runs -> jasmine.unspy(main, 'land')

      isEntry = (index) ->
        expect(main.history.index).toBe index
        entry = main.history.entries[index]
        expect(getEditor().getCursorBufferPosition()).toEqual(entry.point)
        expect(getEditor().getURI()).toBe(entry.URI)

      describe "cursor-history:prev", ->
        it "visit prev entry of cursor history", ->
          runCommand 'cursor-history:prev', -> isEntry(3)
          runCommand 'cursor-history:prev', -> isEntry(2)
          runCommand 'cursor-history:prev', -> isEntry(1)
          runCommand 'cursor-history:prev', -> isEntry(0)

        it "save last position if index is at head(=length of entries)", ->
          expect(main.history.entries.length).toBe 4
          runCommand 'cursor-history:prev', -> isEntry(3)
          runs ->
            expect(main.history.entries.length).toBe 5
            entry = _.last(main.history.entries)
            expect(isEqualEntry(entry, {point: [10, 0], URI: pathSample2})).toBe true

      describe "cursor-history:next", ->
        it "visit next entry of cursor history", ->
          main.history.index = 0
          runCommand 'cursor-history:next', -> isEntry(1)
          runCommand 'cursor-history:next', -> isEntry(2)
          runCommand 'cursor-history:next', -> isEntry(3)

      describe "cursor-history:prev-within-editor", ->
        it "visit prev entry of history within same editor", ->
          runCommand 'cursor-history:prev-within-editor', -> isEntry(3)
          runCommand 'cursor-history:prev-within-editor', -> isEntry(2)

          runs ->
            atom.commands.dispatch(workspaceElement, 'cursor-history:prev-within-editor')
            isEntry(2)

      describe "cursor-history:next-within-editor", ->
        it "visit next entry of history within same editor", ->
          main.history.index = 0

          waitsForPromise ->
            atom.workspace.open(pathSample1)

          runCommand 'cursor-history:next-within-editor', -> isEntry(1)

          runs ->
            atom.commands.dispatch(workspaceElement, 'cursor-history:next-within-editor')
            isEntry(1)

      describe "when editor is destroyed", ->
        getValidEntries = ->
          e for e in main.history.entries when e.isValid()

        beforeEach ->
          expect(getEditor().getURI()).toBe(pathSample2)
          runs ->
            editor2.destroy()
          runs ->
            expect(editor2.isAlive()).toBe false
            expect(getEditor().getURI()).toBe(pathSample1)
            expect(getValidEntries().length).toBe 4

        it "still can reopen and visit entry for once destroyed editor", ->
          runCommand 'cursor-history:prev', -> isEntry(3)
          runCommand 'cursor-history:prev', -> isEntry(2)
          runCommand 'cursor-history:prev', -> isEntry(1)
          runCommand 'cursor-history:prev', -> isEntry(0)
          runCommand 'cursor-history:next', -> isEntry(1)
          runCommand 'cursor-history:next', -> isEntry(2)
          runCommand 'cursor-history:next', -> isEntry(3)

        describe "excludeClosedBuffer setting is true", ->
          beforeEach ->
            atom.config.set('cursor-history.excludeClosedBuffer', true)

          it "skip entry for destroyed editor", ->
            expect(getValidEntries().length).toBe 2
            runCommand 'cursor-history:prev', -> isEntry(1)
            runs ->
              expect(main.history.entries.length).toBe 5
              expect(getValidEntries().length).toBe 3

          it "remove dstroyed entry from history when new entry is added", ->
            expect(getValidEntries().length).toBe 2
            expect(main.history.entries.length).toBe 4
            dispatchCommand(editorElement, 'test:move-down-5')
            expect(editor.getCursorBufferPosition()).toEqual [15, 0]
            entry = _.last(main.history.entries)
            expect(isEqualEntry(entry, {point: [10, 0], URI: pathSample1})).toBe true
            expect(getValidEntries().length).toBe 3
            expect(main.history.entries.length).toBe 3

    describe "ignoreCommands setting", ->
      [editor2, editorElement2] = []
      beforeEach ->
        editor.setCursorBufferPosition([1, 2])
        expect(main.history.entries.length).toBe 0
        expect(editorElement.hasFocus()).toBe true

        jasmine.useRealClock()
        spyOn(atom.workspace, "getActiveTextEditor").andCallThrough()
        atom.commands.add editorElement,
          'test:open-sample2': ->
            atom.workspace.open(pathSample2).then (e) ->
              editor2 = e
              editorElement2 = atom.views.getView(e)

      describe "ignoreCommands is empty", ->
        it "save cursor position to history when editor lost focus", ->
          atom.config.set('cursor-history.ignoreCommands', [])
          runs -> atom.commands.dispatch(editorElement, 'test:open-sample2')
          waitsFor -> atom.workspace.getActiveTextEditor.callCount is 1
          waitsFor -> editorElement2.hasFocus() is true

          runs ->
            expect(main.history.entries.length).toBe 1
            entry = _.last(main.history.entries)
            expect(isEqualEntry(entry, {point: [1, 2], URI: pathSample1})).toBe true

      # FIXME: using realClock clear config.cson completely!!!

      xdescribe "ignoreCommands is set and match command name", ->
        it "won't save cursor position to history when editor lost focus", ->
          main.settings.set('ignoreCommands', ["test:open-sample2"])
          # atom.config.set('cursor-history.ignoreCommands',
          # atom.config.set('cursor-history.ignoreCommands', ["test:open-sample2"])
          runs -> atom.commands.dispatch(editorElement, 'test:open-sample2')
          waitsFor -> editorElement2?.hasFocus() is true

          runs ->
            expect(main.history.entries.length).toBe 0
