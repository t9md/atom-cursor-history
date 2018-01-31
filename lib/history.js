const Entry = require('./entry')

const destroyEntry = entry => entry.destroy()
const isValidEntry = entry => entry.isValid()
const isNotValidEntry = entry => !entry.isValid()

module.exports = class History {
  serialize () {
    return {
      index: this.index,
      entries: this.entries.filter(isValidEntry).map(e => e.serialize())
    }
  }

  static create (state) {
    if (state && state.history) {
      return History.deserialize(state.history)
    } else {
      return new History()
    }
  }

  static deserialize (state) {
    const editorByURI = {}
    const complementEditor = function (entry) {
      const {URI} = entry
      if (!(URI in editorByURI)) {
        editorByURI[URI] = atom.workspace.paneForURI(URI) && atom.workspace.paneForURI(URI).itemForURI(URI)
      }
      entry.editor = editorByURI[URI]
      return entry
    }

    return Object.assign(new History(), {
      index: state.index,
      entries: state.entries.map(complementEditor).map(entry => Entry.deserialize(entry))
    })
  }

  constructor () {
    this.flashMarker = null

    this.init()
    this.configObserver = atom.config.observe('cursor-history.keepSingleEntryPerBuffer', newValue => {
      if (newValue) this.uniqueByBuffer()
    })
  }

  init () {
    this.index = 0
    this.entries = []
  }

  clear () {
    this.entries.forEach(destroyEntry)
    this.init()
  }

  destroy () {
    this.configObserver.dispose()
    this.entries.forEach(destroyEntry)
    this.index = this.entries = this.configObserver = null
  }

  find (direction, editor) {
    return direction === 'next'
      ? this.entries.slice(this.index + 1).find(isJumpableEntry)
      : this.entries
          .slice(0, Math.max(this.index, 0))
          .reverse()
          .find(isJumpableEntry)

    function isJumpableEntry (entry) {
      if (!entry.isValid()) return false

      if (editor) {
        const jumpable = entry.URI ? entry.URI === editor.getURI() : entry.editor === editor
        if (!jumpable) return false
      }

      if (atom.config.get('cursor-history.searchAllPanes')) {
        return true
      } else {
        // When entry have URI we can open on any pane.
        // If not, it's editor must be already exist in current pane.
        return (
          entry.URI ||
          atom.workspace
            .getActivePane()
            .getItems()
            .includes(entry.editor)
        )
      }
    }
  }

  isIndexAtHead () {
    return this.index === this.entries.length
  }

  setIndexToHead () {
    // Since we know we can set index at entries.length, we can safely remove invalid entries here.
    this.removeInvalidEntries()

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
  add (location, {setIndexToHead = true} = {}) {
    const newEntry = new Entry(location)
    if (atom.config.get('cursor-history.keepSingleEntryPerBuffer')) {
      const isSameURI = entry => newEntry.URI === entry.URI
      this.entries.filter(isSameURI).forEach(destroyEntry)
    } else {
      const isAtSameRow = entry => newEntry.isAtSameRow(entry)
      this.entries.filter(isAtSameRow).forEach(destroyEntry)
    }

    this.entries.push(newEntry)

    if (setIndexToHead) {
      this.setIndexToHead()
    }
    if (atom.config.get('cursor-history.debug') && location.reason) {
      this.log(`${location.reason} [${location.command}]`)
    }
  }

  uniqueByBuffer () {
    if (!this.entries.length) return
    const URIs = new Set()
    for (const entry of this.entries.slice().reverse()) {
      if (URIs.has(entry.URI)) entry.destroy()
      else URIs.add(entry.URI)
    }
    this.setIndexToHead()
  }

  removeInvalidEntries () {
    // Scrub invalid
    this.entries.filter(isNotValidEntry).forEach(destroyEntry)
    this.entries = this.entries.filter(isValidEntry)

    // Remove if exceeds max
    const removeCount = this.entries.length - atom.config.get('cursor-history.max')
    if (removeCount > 0) {
      this.entries.splice(0, removeCount).forEach(destroyEntry)
    }
  }

  inspect (msg) {
    const entries = this.entries.slice()
    if (this.index === this.entries.length) {
      entries.push({inspect: () => ''})
    }

    return entries.map((e, i) => `${i === this.index ? '> ' : '  '}${i}: ${e.inspect()}`).join('\n')
  }

  log (msg) {
    console.log(`# cursor-history: ${msg}\n${this.inspect()}\n\n`)
  }

  // Why we need to remove duplicate entries inspiteof removeing same row entry in add() tining?
  // When editor content was modified like relacing whole editor content by atom-pritter.
  // It update all existing marker position into same position which make history useless.
  // See #36 for detail.
  destroyDuplicateEntries () {
    const seen = new Set()
    for (const entry of this.entries.filter(isValidEntry)) {
      const stringOfEntry = entry.toString()
      if (seen.has(stringOfEntry)) entry.destroy()
      else seen.add(stringOfEntry)
    }
  }

  jump (editor, direction, {withinEditor} = {}) {
    const origialURI = editor.getPath()
    const wasAtHead = this.isIndexAtHead()
    const searchAllPanes = atom.config.get('cursor-history.searchAllPanes')

    this.destroyDuplicateEntries()
    const entry = this.find(direction, withinEditor ? editor : undefined)
    if (!entry) return

    this.index = this.entries.indexOf(entry)

    // FIXME, Explicitly preserve point, URI by setting independent value,
    // since its might be set null if entry.isAtSameRow()
    const copiedEntry = Object.assign({}, entry)

    if (direction === 'prev' && wasAtHead) {
      const location = {
        editor,
        point: editor.getCursorBufferPosition(),
        URI: origialURI
      }
      this.add(location, {setIndexToHead: false})
    }

    if (copiedEntry.editor && !copiedEntry.URI) {
      const pane = atom.workspace.getCenter().paneForItem(copiedEntry.editor)
      if (!pane) {
        throw new Error(`no pane found for ${editor}`)
        // this.log('NO PANE FOUND')
        // entry.destroy()
      }
      pane.activate()
      pane.activateItem(copiedEntry.editor)
      this.land(copiedEntry.editor, copiedEntry.point, direction, true)
      return
    }

    atom.workspace.open(copiedEntry.URI, {searchAllPanes}).then(editor => {
      this.land(editor, copiedEntry.point, direction, origialURI === copiedEntry.URI)
    })
  }

  land (editor, point, direction, isSameURI) {
    const originalRow = editor.getCursorBufferPosition().row
    editor.setCursorBufferPosition(point, {autoscroll: false})
    editor.scrollToCursorPosition({center: true})

    if (atom.config.get('cursor-history.flashOnLand')) {
      if (!isSameURI || originalRow !== point.row) {
        this.flash(editor)
      }
    }

    if (atom.config.get('cursor-history.debug')) this.log(direction)
  }

  flash (editor) {
    if (this.flashMarker) this.flashMarker.destroy()
    this.flashMarker = editor.markBufferPosition(editor.getCursorBufferPosition())
    editor.decorateMarker(this.flashMarker, {type: 'line', class: 'cursor-history-flash-line'})

    let disposable

    const destroyMarker = () => {
      if (disposable) {
        disposable.dispose()
        disposable = null
      }
      if (this.flashMarker) {
        this.flashMarker.destroy()
        this.flashMarker = null
      }
    }

    disposable = editor.onDidChangeCursorPosition(destroyMarker)
    // [NOTE] animation-duration has to be shorter than this value(1sec)
    setTimeout(destroyMarker, 1000)
  }
}
