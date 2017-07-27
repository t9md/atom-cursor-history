const Entry = require("./entry")

const destroyEntry = entry => entry.destroy()
const isValidEntry = entry => entry.isValid()
const isNotValidEntry = entry => !entry.isValid()

module.exports = class History {
  serialize() {
    return {
      index: this.index,
      entries: this.entries.filter(isValidEntry).map(e => e.serialize()),
    }
  }

  static deserialize(createLocation, state) {
    const editorByURI = {}
    const complementEditor = function(entry) {
      const {URI} = entry
      if (!(URI in editorByURI)) {
        editorByURI[URI] =
          atom.workspace.paneForURI(URI) && atom.workspace.paneForURI(URI).itemForURI(URI)
      }
      entry.editor = editorByURI[URI]
      return entry
    }

    return Object.assign(new this(createLocation), {
      index: state.index,
      entries: state.entries.map(complementEditor).map(entry => Entry.deserialize(entry)),
    })
  }

  constructor(createLocation) {
    this.createLocation = createLocation
    this.flashMarker = null

    this.init()
    this.configObserver = atom.config.observe(
      "cursor-history.keepSingleEntryPerBuffer",
      newValue => {
        if (newValue) this.uniqueByBuffer()
      }
    )
  }

  init() {
    this.index = 0
    this.entries = []
  }

  clear() {
    this.entries.forEach(destroyEntry)
    this.init()
  }

  destroy() {
    this.configObserver.dispose()
    this.entries.forEach(destroyEntry)
    this.index = this.entries = this.configObserver = null
  }

  findValidEntry(direction, {URI} = {}) {
    const isValid = entry => entry.isValid() && (URI ? entry.URI === URI : true)
    if (direction === "next") {
      return this.entries.slice(this.index + 1).find(isValid)
    } else {
      return this.entries.slice(0, Math.max(this.index, 0)).reverse().find(isValid)
    }
  }

  get(direction, options = {}) {
    const entry = this.findValidEntry(direction, options)
    if (entry) {
      this.index = this.entries.indexOf(entry)
      return entry
    }
  }

  isIndexAtHead() {
    return this.index === this.entries.length
  }

  setIndexToHead() {
    this.index = this.entries.length
    return this.index
  }

  // History concatenation mimicking Vim's way.
  // newEntry(=old position from where you jump to land here) is
  // *always* added to end of @entries.
  // Whenever newEntry is added old Marker wich have same row with
  // newEntry is removed.
  // This allows you to get back to old position(row) only once.
  //
  //  http://vimhelp.appspot.com/motion.txt.html#jump-motions
  //
  // e.g
  //  1st column: index of @entries
  //  2nd column: row of each Marker indicate.
  //  >: indicate @index
  //
  // Case-1:
  //   Jump from row=7 to row=9 then back with `cursor-history:prev`.
  //
  //     [1]   [2]    [3]
  //     0 1   0 1    0 1
  //     1 3   1 3    1 3
  //     2 5   2 5    2 5
  //   > 3 7   3 8    3 8
  //     4 8   4 7  > 4 7
  //         >   _    5 9
  //
  // 1. Initial State, @index=3(row=7)
  // 2. Jump from row=7 to row=9, newEntry(row=7) is appended to end
  //    of @entries then old row=7(@index=3) was deleted.
  //    @index adjusted to head of @entries(@index = @entries.length).
  // 3. Back from row=9 to row=7 with `cursor-history:prev`.
  //    newEntry(row=9) is appended to end of @entries.
  //    No special @index adjustment.
  //
  // Case-2:
  //  Jump from row=3 to row=7 then back with `cursor-history.prev`.
  //
  //     [1]   [2]    [3]
  //     0 1   0 1    0 1
  //   > 1 3   1 5    1 5
  //     2 5   2 7    2 8
  //     3 7   3 8  > 3 3
  //     4 8   4 3    4 7
  //         >   _
  //
  // 1. Initial State, @index=1(row=3)
  // 2. Jump from row=3 to row=7, newEntry(row=3) is appended to end
  //    of @entries then old row=3(@index=1) was deleted.
  //    @index adjusted to head of @entries(@index = @entries.length).
  // 3. Back from row=7 to row=3 with `cursor-history:prev`.
  //    newEntry(row=7) is appended to end of @entries.
  //    No special @index adjustment.
  //
  add(location, {subject, setIndexToHead = true, log = true} = {}) {
    const newEntry = new Entry(location)
    let entry
    if (atom.config.get("cursor-history.keepSingleEntryPerBuffer")) {
      const isSameURI = entry => newEntry.URI === entry.URI
      this.entries.filter(isSameURI).forEach(destroyEntry)
    } else {
      const isAtSameRow = entry => newEntry.isAtSameRow(entry)
      this.entries.filter(isAtSameRow).forEach(destroyEntry)
    }

    this.entries.push(newEntry)
    // Only when we are allowed to modify index, we can safely remove this.entries.
    if (setIndexToHead) {
      this.removeInvalidEntries()
      this.setIndexToHead()
    }
    if (atom.config.get("cursor-history.debug") && log) {
      this.log(`${subject} [${location.type}]`)
    }
  }

  uniqueByBuffer() {
    if (!this.entries.length) return
    const URIs = new Set()
    for (const entry of this.entries.slice().reverse()) {
      if (URIs.has(entry.URI)) {
        entry.destroy()
      } else {
        URIs.add(entry.URI)
      }
    }
    this.removeInvalidEntries()
    this.setIndexToHead()
  }

  removeInvalidEntries() {
    // Scrub invalid
    this.entries.filter(isNotValidEntry).forEach(destroyEntry)
    this.entries = this.entries.filter(isValidEntry)

    // Remove if exceeds max
    const removeCount = this.entries.length - atom.config.get("cursor-history.max")
    if (removeCount > 0) {
      this.entries.splice(0, removeCount).forEach(destroyEntry)
    }
  }

  inspect(msg) {
    const entries = this.entries.slice()
    if (this.index == this.entries.length) {
      entries.push({inspect: () => ""})
    }

    return entries.map((e, i) => `${i === this.index ? "> " : "  "}${i}: ${e.inspect()}`).join("\n")
  }

  log(msg) {
    console.log(`# cursor-history: ${msg}\n${this.inspect()}\n\n`)
  }

  // Why we need to remove duplicate entries inspiteof removeing same row entry in add() tining?
  // When editor content was modified like relacing whole editor content by atom-pritter.
  // It update all existing marker position into same position which make history useless.
  // See #36 for detail.
  destroyDuplicateEntries() {
    const seen = new Set()
    for (const entry of this.entries.filter(isValidEntry)) {
      const stringOfEntry = entry.toString()
      if (seen.has(stringOfEntry)) {
        entry.destroy()
      } else {
        seen.add(stringOfEntry)
      }
    }
  }

  jump(editor, direction, {withinEditor} = {}) {
    this.destroyDuplicateEntries()

    const origialURI = editor.getPath()
    const wasAtHead = this.isIndexAtHead()
    const getOptions = withinEditor ? {URI: origialURI} : {}
    const entry = this.get(direction, getOptions)
    if (entry == null) return

    // FIXME, Explicitly preserve point, URI by setting independent value,
    // since its might be set null if entry.isAtSameRow()
    const {point, URI} = entry

    if (direction === "prev" && wasAtHead) {
      const location = this.createLocation(editor, "prev")
      this.add(location, {setIndexToHead: false, log: false, subject: "Save head position"})
    }

    const searchAllPanes = atom.config.get("cursor-history.searchAllPanes")
    atom.workspace.open(URI, {searchAllPanes}).then(editor => {
      this.land(editor, point, direction, origialURI === URI)
    })
  }

  land(editor, point, direction, isSameURI) {
    const originalRow = editor.getCursorBufferPosition().row
    editor.setCursorBufferPosition(point, {autoscroll: false})
    editor.scrollToCursorPosition({center: true})

    if (atom.config.get("cursor-history.flashOnLand")) {
      if (!isSameURI || originalRow !== point.row) {
        this.flash(editor)
      }
    }

    if (atom.config.get("cursor-history.debug")) this.log(direction)
  }

  flash(editor) {
    if (this.flashMarker) this.flashMarker.destroy()
    this.flashMarker = editor.markBufferPosition(editor.getCursorBufferPosition())
    editor.decorateMarker(this.flashMarker, {
      type: "line",
      class: "cursor-history-flash-line",
    })

    let disposable = null
    const destroyMarker = () => {
      if (disposable) disposable.dispose()
      disposable = null
      if (this.flashMarker) this.flashMarker.destroy()
    }

    disposable = editor.onDidChangeCursorPosition(destroyMarker)
    // [NOTE] animation-duration has to be shorter than this value(1sec)
    setTimeout(destroyMarker, 1000)
  }
}
