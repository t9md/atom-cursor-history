CursorHistory = require '../lib/history'

describe "CursorHistory", ->
  [cursorHistory] = []

  beforeEach ->
    cursorHistory = new CursorHistory

  describe "when the CursorHistory is initialized", ->
    it "length is zero", ->
      expect(cursorHistory.entries.length).toBe(0)
    it "next() is undefined", ->
      expect(cursorHistory.next()).toBe(undefined)
    it "prev() is undefined", ->
      expect(cursorHistory.prev()).toBe(undefined)
