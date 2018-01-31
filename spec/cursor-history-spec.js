'use babel'
const {Point} = require('atom')
const {it, fit, ffit, fffit, emitterEventPromise, beforeEach, afterEach} = require('./async-spec-helpers') // eslint-disable-line no-unused-vars

const setConfig = (param, value) => atom.config.set(`cursor-history.${param}`, value)

const getEditor = () => atom.workspace.getActiveTextEditor()

const dispatchCommand = function (element, command) {
  atom.commands.dispatch(element, command)
  return advanceClock(100)
}

global.beforeEach(function () {
  this.addMatchers({
    toBeEqualEntry (expected) {
      return (
        this.actual.URI === expected.URI &&
        Point.fromObject(this.actual.point).isEqual(Point.fromObject(expected.point))
      )
    }
  })
})

describe('cursor-history', () => {
  let editor, editorElement, main, pathSample1, pathSample2

  function getEntries (which = null) {
    const {entries} = main.history
    switch (which) {
      case 'last':
        return entries.slice(-1)[0]
      case 'first':
        return entries[0]
      default:
        return entries
    }
  }

  beforeEach(async () => {
    atom.commands.add('atom-text-editor', {
      'test:move-down-2' () {
        this.getModel().moveDown(2)
      },
      'test:move-down-5' () {
        this.getModel().moveDown(5)
      },
      'test:move-up-2' () {
        this.getModel().moveUp(2)
      },
      'test:move-up-5' () {
        this.getModel().moveUp(5)
      }
    })

    pathSample1 = atom.project.resolvePath('sample-1.coffee')
    pathSample2 = atom.project.resolvePath('sample-2.coffee')
    jasmine.attachToDOM(atom.workspace.getElement())

    const pack = await atom.packages.activatePackage('cursor-history')
    main = pack.mainModule
    editor = await atom.workspace.open(pathSample1)
    editorElement = editor.element
  })

  describe('initial state of history entries', () => {
    it('is empty', () => {
      expect(main.history).not.toBeTruthy()
    })
  })

  describe('history saving', () => {
    describe('cursor moved', () => {
      it('save history when cursor moved over 4 line by default', () => {
        editor.setCursorBufferPosition([0, 5])
        dispatchCommand(editorElement, 'test:move-down-5')
        expect(getEntries()).toHaveLength(1)
        expect(getEntries('first')).toBeEqualEntry({point: [0, 5], URI: pathSample1})
      })

      it('can save multiple entry', () => {
        dispatchCommand(editorElement, 'test:move-down-5')
        dispatchCommand(editorElement, 'test:move-down-5')
        dispatchCommand(editorElement, 'test:move-down-5')
        const entries = getEntries()
        expect(entries).toHaveLength(3)
        const [e1, e2, e3] = Array.from(entries)
        expect(e1).toBeEqualEntry({point: [0, 0], URI: pathSample1})
        expect(e2).toBeEqualEntry({point: [5, 0], URI: pathSample1})
        expect(e3).toBeEqualEntry({point: [10, 0], URI: pathSample1})
      })

      it('wont save history if line delta of move is less than 4 line', () => {
        dispatchCommand(editorElement, 'core:move-down')
        expect(editor.getCursorBufferPosition()).toEqual([1, 0])
        expect(main.history).not.toBeTruthy()

        dispatchCommand(editorElement, 'test:move-down-5')
        expect(editor.getCursorBufferPosition()).toEqual([6, 0])
        const entries = getEntries()
        expect(entries).toHaveLength(1)
        expect(entries[0]).toBeEqualEntry({point: [1, 0], URI: pathSample1})
        dispatchCommand(editorElement, 'core:move-down')
        expect(editor.getCursorBufferPosition()).toEqual([7, 0])
        expect(getEntries()).toBe(entries)
      })

      it('remove older entry if its row is same as new entry', () => {
        dispatchCommand(editorElement, 'test:move-down-5')
        dispatchCommand(editorElement, 'test:move-down-5')
        dispatchCommand(editorElement, 'test:move-up-5')
        let entries = getEntries()
        expect(entries).toHaveLength(3)
        let [e1, e2, e3] = entries
        expect(e1).toBeEqualEntry({point: [0, 0], URI: pathSample1})
        expect(e2).toBeEqualEntry({point: [5, 0], URI: pathSample1})
        expect(e3).toBeEqualEntry({point: [10, 0], URI: pathSample1})

        expect(editor.getCursorBufferPosition()).toEqual([5, 0])
        editor.setCursorBufferPosition([5, 5])
        expect(editor.getCursorBufferPosition()).toEqual([5, 5])
        dispatchCommand(editorElement, 'test:move-up-5')

        entries = getEntries()
        expect(entries).toHaveLength(3)
        ;[e1, e2, e3] = entries
        expect(e1).toBeEqualEntry({point: [0, 0], URI: pathSample1})
        expect(e2).toBeEqualEntry({point: [10, 0], URI: pathSample1})
        expect(e3).toBeEqualEntry({point: [5, 5], URI: pathSample1})
      })
    })

    describe('rowDeltaToRemember settings', () => {
      beforeEach(() => {
        setConfig('rowDeltaToRemember', 1)
      })

      describe('when set to 1', () => {
        it('save history when cursor move over 1 line', () => {
          editor.setCursorBufferPosition([0, 5])
          dispatchCommand(editorElement, 'test:move-down-2')
          expect(editor.getCursorBufferPosition()).toEqual([2, 5])
          expect(getEntries()).toHaveLength(1)
          expect(getEntries('first')).toBeEqualEntry({point: [0, 5], URI: pathSample1})

          dispatchCommand(editorElement, 'test:move-down-2')
          expect(editor.getCursorBufferPosition()).toEqual([4, 5])
          expect(getEntries()).toHaveLength(2)
          expect(getEntries('last')).toBeEqualEntry({point: [2, 5], URI: pathSample1})
        })
      })
    })
  })

  describe('go/back history with next/prev commands', () => {
    const isInitialStateOfBeforeHistoryInitialized = () => {
      expect(main.history).not.toBeTruthy()
      expect(editor.getCursorBufferPosition()).toEqual([0, 0])
    }

    const isInitialStateOfAfterHistoryInitialized = () => {
      expect(getEntries()).toHaveLength(0)
      expect(editor.getCursorBufferPosition()).toEqual([0, 0])
    }

    beforeEach(() => {
      isInitialStateOfBeforeHistoryInitialized()
    })

    describe('when history is empty', () => {
      it('do nothing with next', () => {
        dispatchCommand(editorElement, 'cursor-history:next')
        isInitialStateOfAfterHistoryInitialized()
      })
      it('do nothing with prev', () => {
        dispatchCommand(editorElement, 'cursor-history:prev')
        isInitialStateOfAfterHistoryInitialized()
      })
      it('do nothing with next-within-editor', () => {
        dispatchCommand(editorElement, 'cursor-history:next-within-editor')
        isInitialStateOfAfterHistoryInitialized()
      })
      it('do nothing with prev-within-editor', () => {
        dispatchCommand(editorElement, 'cursor-history:prev-within-editor')
        isInitialStateOfAfterHistoryInitialized()
      })
    })

    describe('when history is not empty', () => {
      let editor2, editorElement2
      beforeEach(async () => {
        dispatchCommand(editorElement, 'test:move-down-5')
        dispatchCommand(editorElement, 'test:move-down-5')

        editor2 = await atom.workspace.open(pathSample2)
        editorElement2 = editor2.element
        dispatchCommand(editorElement2, 'test:move-down-5')
        dispatchCommand(editorElement2, 'test:move-down-5')
        const entries = getEntries()
        expect(entries).toHaveLength(4)
        expect(main.history.indexIsAtHead()).toBe(true)
        expect(getEditor().getURI()).toBe(pathSample2)
        expect(getEditor().getCursorBufferPosition()).toEqual([10, 0])
      })

      const runCommand = function (command, fn) {
        runs(() => {
          spyOn(main.history, 'land').andCallThrough()
          const activeEditor = atom.workspace.getActiveTextEditor()
          atom.commands.dispatch(activeEditor.element, command)
        })
        waitsFor(() => main.history.land.callCount === 1)
        runs(() => fn())
        runs(() => jasmine.unspy(main.history, 'land'))
      }

      const isEntry = function (index) {
        expect(main.history.index).toBe(index)
        const entry = getEntries()[index]
        expect(getEditor().getCursorBufferPosition()).toEqual(entry.point)
        expect(getEditor().getURI()).toBe(entry.URI)
      }

      describe('cursor-history:prev', () => {
        it('visit prev entry of cursor history', () => {
          runCommand('cursor-history:prev', () => isEntry(3))
          runCommand('cursor-history:prev', () => isEntry(2))
          runCommand('cursor-history:prev', () => isEntry(1))
          runCommand('cursor-history:prev', () => isEntry(0))
        })

        it('save last position if index is at head(=length of entries)', () => {
          expect(getEntries()).toHaveLength(4)
          runCommand('cursor-history:prev', () => {
            isEntry(3)
            expect(getEntries()).toHaveLength(5)
            expect(getEntries('last')).toBeEqualEntry({point: [10, 0], URI: pathSample2})
          })
        })
      })

      describe('cursor-history:next', () =>
        it('visit next entry of cursor history', () => {
          main.history.index = 0
          runCommand('cursor-history:next', () => isEntry(1))
          runCommand('cursor-history:next', () => isEntry(2))
          runCommand('cursor-history:next', () => isEntry(3))
        }))

      describe('cursor-history:prev-within-editor', () =>
        it('visit prev entry of history within same editor', () => {
          runCommand('cursor-history:prev-within-editor', () => isEntry(3))
          runCommand('cursor-history:prev-within-editor', () => isEntry(2))
          runs(() => {
            const editor = atom.workspace.getActiveTextEditor()
            atom.commands.dispatch(editor.element, 'cursor-history:prev-within-editor')
            isEntry(2)
          })
        }))

      describe('cursor-history:next-within-editor', () => {
        it('visit next entry of history within same editor', async () => {
          main.history.index = 0

          await atom.workspace.open(pathSample1)

          runCommand('cursor-history:next-within-editor', () => isEntry(1))

          runs(() => {
            const editor = atom.workspace.getActiveTextEditor()
            atom.commands.dispatch(editor.element, 'cursor-history:next-within-editor')
            isEntry(1)
          })
        })
      })

      describe('when editor is destroyed', () => {
        const getValidEntries = () =>
          getEntries()
            .filter(e => e.isValid())
            .map(e => e)

        beforeEach(() => {
          expect(getEditor().getURI()).toBe(pathSample2)
          runs(() => editor2.destroy())
          runs(() => {
            expect(editor2.isAlive()).toBe(false)
            expect(getEditor().getURI()).toBe(pathSample1)
            expect(getValidEntries()).toHaveLength(4)
          })
        })

        it('still can reopen and visit entry for once destroyed editor', () => {
          runCommand('cursor-history:prev', () => isEntry(3))
          runCommand('cursor-history:prev', () => isEntry(2))
          runCommand('cursor-history:prev', () => isEntry(1))
          runCommand('cursor-history:prev', () => isEntry(0))
          runCommand('cursor-history:next', () => isEntry(1))
          runCommand('cursor-history:next', () => isEntry(2))
          runCommand('cursor-history:next', () => isEntry(3))
        })

        describe('excludeClosedBuffer setting is true', () => {
          beforeEach(() => {
            setConfig('excludeClosedBuffer', true)
          })

          it('skip entry for destroyed editor', () => {
            expect(getValidEntries()).toHaveLength(2)
            runCommand('cursor-history:prev', () => isEntry(1))
            runs(() => {
              expect(getEntries()).toHaveLength(5)
              expect(getValidEntries()).toHaveLength(3)
            })
          })

          it('remove dstroyed entry from history when new entry is added', () => {
            expect(getValidEntries()).toHaveLength(2)
            expect(getEntries()).toHaveLength(4)
            dispatchCommand(editorElement, 'test:move-down-5')
            expect(editor.getCursorBufferPosition()).toEqual([15, 0])
            expect(getEntries('last')).toBeEqualEntry({point: [10, 0], URI: pathSample1})
            expect(getValidEntries()).toHaveLength(3)
            expect(getEntries()).toHaveLength(3)
          })
        })
      })

      describe('keepSingleEntryPerBuffer settings', () =>
        describe('when set to true', () => {
          it('keep only latest entry per buffer and remove other entries', () => {
            expect(getEntries()).toHaveLength(4)
            setConfig('keepSingleEntryPerBuffer', true)
            expect(getEntries()).toHaveLength(2)
            const entries = getEntries()
            expect(entries[0].URI).toBe(pathSample1)
            expect(entries[0].point).toEqual([5, 0])
            expect(entries[1].URI).toBe(pathSample2)
            expect(entries[1].point).toEqual([5, 0])
          })

          it('keep only latest entry per buffer and remove other entries', () => {
            expect(getEntries()).toHaveLength(4)
            setConfig('keepSingleEntryPerBuffer', true)
            expect(getEntries()).toHaveLength(2)
            expect(editor2.getCursorBufferPosition()).toEqual([10, 0])
            dispatchCommand(editorElement2, 'test:move-up-5')
            const entries = getEntries()
            expect(entries).toHaveLength(2)
            expect(main.history.indexIsAtHead()).toBe(true)
            expect(entries[1].URI).toBe(pathSample2)
            expect(entries[1].point).toEqual([10, 0])
          })
        }))
    })

    describe('ignoreCommands setting', () => {
      beforeEach(() => {
        editor.setCursorBufferPosition([1, 2])
        expect(main.history).not.toBeTruthy()
        expect(editorElement.hasFocus()).toBe(true)
        atom.commands.add(editorElement, {
          'test:open-sample2' () {
            atom.workspace.open(pathSample2)
          }
        })
      })

      describe('ignoreCommands is empty', () => {
        it('save cursor position to history when editor lost focus', () => {
          setConfig('ignoreCommands', [])
          jasmine.useRealClock()
          runs(() => atom.commands.dispatch(editorElement, 'test:open-sample2'))
          waitsFor(() => main.history)
          runs(() => {
            expect(getEntries()).toHaveLength(1)
            expect(getEntries('last')).toBeEqualEntry({point: [1, 2], URI: pathSample1})
          })
        })
      })

      describe('ignoreCommands is set and match command name', () => {
        const dispatchCommand = commandName => {
          return new Promise(resolve => {
            const disposable = atom.commands.onWillDispatch(({type}) => {
              if (type === commandName) {
                disposable.dispose()
                resolve(main.trackedLocation)
              }
            })
            atom.commands.dispatch(editorElement, commandName)
          })
        }

        it('track location change when editor lost focus', async () => {
          expect(await dispatchCommand('test:open-sample2')).toBeTruthy()
        })

        it("Doesn't track location change when editor lost focus", async () => {
          setConfig('ignoreCommands', ['test:open-sample2'])
          expect(await dispatchCommand('test:open-sample2')).toBeFalsy()
        })
      })
    })
  })
})
