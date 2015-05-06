CursorHistory = require '../lib/cursor-history'
{Point} = require "atom"

describe "CursorHistory", ->
  [cursorHistory] = []

  beforeEach ->
    cursorHistory = new CursorHistory

  describe "when the CursorHistory is initialized", ->
    it "length is zero", ->
      expect(cursorHistory.getLength()).toBe(0)
    it "next() is undefined", ->
      expect(cursorHistory.next()).toBe(undefined)
    it "prev() is undefined", ->
      expect(cursorHistory.prev()).toBe(undefined)

  describe "when two entries added", ->
    p1 = new Point(1,1)
    p2 = new Point(2,1)
    p3 = new Point(3,1)

    it "length is 2", ->
      cursorHistory.add(p1)
      cursorHistory.add(p2)
      cursorHistory.add(p3)
      expect(cursorHistory.getLength()).toBe(3)

      expect(cursorHistory.prev().isEqual(p3)).toBe(true)
      expect(cursorHistory.prev().isEqual(p2)).toBe(true)
      expect(cursorHistory.prev().isEqual(p1)).toBe(true)
      expect(cursorHistory.prev()).toBe(undefined)

      expect(cursorHistory.next().isEqual(p1)).toBe(true)
      expect(cursorHistory.next().isEqual(p2)).toBe(true)
      expect(cursorHistory.next().isEqual(p3)).toBe(true)
      expect(cursorHistory.next()).toBe(undefined)
