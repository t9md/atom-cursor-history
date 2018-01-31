const Entry = require('./entry')

function getConfig (param) {
  return atom.config.get(`cursor-history.${param}`)
}

function functionForDuplicateBy (fn) {
  const seen = new Set()
  return function (entry) {
    const key = fn(entry)
    const isDuplicate = seen.has(key)
    if (!isDuplicate) {
      seen.add(key)
    }
    return isDuplicate
  }
}

module.exports = class History {
  serialize () {
    return {
      index: this.index,
      entries: this.getValidEntries().map(e => e.serialize())
    }
  }

  static deserialize (state) {
    return Object.assign(new History(), {
      index: state.index,
      entries: state.entries.map(entry => Entry.deserialize(entry))
    })
  }

  static create (state) {
    if (state && state.history) {
      return History.deserialize(state.history)
    } else {
      return new History()
    }
  }

  constructor () {
    this.init()
    this.destroyFlash = this.destroyFlash.bind(this)
    this.configObserver = atom.config.observe('cursor-history.keepSingleEntryPerBuffer', value => {
      if (value) this.uniqueByBuffer()
    })
  }

  init () {
    this.index = 0
    this.entries = []
  }

  clear () {
    this.destroyEntries(this.entries)
    this.init()
  }

  getValidEntries () {
    return this.entries.filter(entry => entry.isValid())
  }

  destroyEntries (entries, fn) {
    for (const entry of entries) {
      if (!fn || fn(entry)) {
        entry.destroy()
      }
    }
  }

  destroy () {
    this.configObserver.dispose()
    this.destroyEntries(this.entries)
    this.index = this.entries = this.configObserver = null
  }

  findIndex (direction, editor) {
    if (direction === 'next') {
      for (let i = this.index + 1; i < this.entries.length; i++) {
        if (this.isJumpableEntry(this.entries[i], editor)) {
          return i
        }
      }
    } else if (direction === 'prev') {
      for (let i = this.index - 1; i >= 0; i--) {
        if (this.isJumpableEntry(this.entries[i], editor)) {
          return i
        }
      }
    }
    return -1
  }

  isJumpableEntry (entry, editor) {
    if (!entry.isValid()) return false

    if (editor) {
      const jumpable = entry.URI ? entry.URI === editor.getURI() : entry.editor === editor
      if (!jumpable) return false
    }

    // When entry have URI we can open on any pane.
    // If not, it's editor must be already exist in current pane.
    if (getConfig('searchAllPanes')) {
      return true
    } else {
      return (
        entry.URI ||
        atom.workspace
          .getActivePane()
          .getItems()
          .includes(entry.editor)
      )
    }
  }

  indexIsAtHead () {
    return this.index === this.entries.length
  }

  setIndexToHead () {
    // We will set index to entries.length, which means index will not point to valid entry.
    // Thus, we can splice dirty entries this time!!
    // Scrub invalid
    this.destroyEntries(this.entries, entry => !entry.isValid())
    this.entries = this.getValidEntries()

    // Enforce max history limit
    const removeCount = this.entries.length - getConfig('max')
    if (removeCount > 0) {
      this.destroyEntries(this.entries.splice(0, removeCount))
    }

    this.index = this.entries.length
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
    if (setIndexToHead) {
      if (getConfig('keepSingleEntryPerBuffer')) {
        this.destroyEntries(this.entries, entry => newEntry.URI === entry.URI)
      } else {
        this.destroyEntries(this.entries, entry => newEntry.isAtSameRow(entry))
      }
    }

    this.entries.push(newEntry)

    if (setIndexToHead) {
      this.setIndexToHead()
    }

    if (location.reason) {
      this.debug(`${location.reason} [${location.command}]`)
    }
  }

  uniqueByBuffer () {
    const isDuplicate = functionForDuplicateBy(entry => entry.URI)
    this.destroyEntries(this.entries.slice().reverse(), isDuplicate)
    this.setIndexToHead()
  }

  // Why we need to remove duplicate entries in spite of removeing same row entry in add() timing?
  // When editor content was modified like relacing whole editor content by atom-prittier.
  // It update all existing marker position into same position which make history useless.
  // See #36 for detail.
  destroyDuplicateEntries () {
    const entries = this.getValidEntries()
    const isDuplicate = functionForDuplicateBy(entry => entry.toString())
    this.destroyEntries(entries.slice().reverse(), isDuplicate)
  }

  async jump (editor, direction, editorToFind) {
    this.destroyDuplicateEntries()
    const index = this.findIndex(direction, editorToFind)
    if (index === -1) {
      return
    }

    const fromURI = editor.getURI()

    // NOTE
    // indexIsAtHead() check must be done BEFORE updating index on next line
    // Why also need postpoine excution by pendingAddHistory() is
    // this.add() invalidate invalid entry.
    if (direction === 'prev' && this.indexIsAtHead()) {
      const location = {
        editor: editor,
        point: editor.getCursorBufferPosition(),
        URI: fromURI
      }
      this.add(location, {setIndexToHead: false})
    }

    this.index = index
    const entry = this.entries[index]

    let landingEditor, isSameURI
    if (entry.editor && !entry.URI) {
      const pane = atom.workspace.getCenter().paneForItem(entry.editor)
      if (!pane) {
        throw new Error(`no pane found for ${editor}`)
      }
      pane.activate()
      pane.activateItem(entry.editor)

      landingEditor = entry.editor
      isSameURI = true
    } else {
      landingEditor = await atom.workspace.open(entry.URI, {searchAllPanes: getConfig('searchAllPanes')})
      isSameURI = entry.URI === fromURI
    }

    this.land(landingEditor, entry, isSameURI)
    this.debug(direction)
  }

  land (editor, entry, isSameURI) {
    const oldRow = editor.getCursorBufferPosition().row
    const point = entry.point
    editor.setCursorBufferPosition(point, {autoscroll: false})
    editor.scrollToCursorPosition({center: true})

    if (getConfig('flashOnLand') && (!isSameURI || oldRow !== point.row)) {
      this.flash(editor)
    }
  }

  flash (editor) {
    this.destroyFlash()

    this.flashMarker = editor.markBufferPosition(editor.getCursorBufferPosition())
    editor.decorateMarker(this.flashMarker, {type: 'line', class: 'cursor-history-flash-line'})

    this.onCursorChangeDisposable = editor.onDidChangeCursorPosition(this.destroyFlash)
    this.flashTimeout = setTimeout(this.destroyFlash, 800) // 800ms sync with animation-duration in CSS.
  }

  destroyFlash () {
    if (this.flashTimeout) {
      clearTimeout(this.flashTimeout)
      this.flashTimeout = null
    }
    if (this.flashMarker) {
      this.flashMarker.destroy()
      this.flashMarker = null
    }
    if (this.onCursorChangeDisposable) {
      this.onCursorChangeDisposable.dispose()
      this.onCursorChangeDisposable = null
    }
  }

  inspect (msg) {
    const entries = this.entries.slice()
    if (this.index === this.entries.length) {
      entries.push({inspect: () => ''})
    }
    const linePrefix = i => (i === this.index ? '> ' : '  ')

    return entries.map((e, i) => `${linePrefix(i)}${i}: ${e.inspect()}`).join('\n')
  }

  debug (msg) {
    if (getConfig('debug')) {
      console.log(`# cursor-history: ${msg}\n${this.inspect()}\n\n`)
    }
  }
}
