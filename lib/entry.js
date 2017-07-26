const {CompositeDisposable, Point} = require("atom")
const {existsSync} = require("fs")
const path = require("path")

// Wrapper for Point or Marker.
//  For alive editor, use Marker to track up to date position.
//  For destroyed editor, use Point.
module.exports = class Entry {
  static deserialize({editor, point, URI}) {
    return new this({editor, point: Point.fromObject(point), URI})
  }

  serialize() {
    return {
      point: this.point.serialize(),
      URI: this.URI,
    }
  }

  constructor({editor, point, URI}) {
    this.point = point
    this.URI = URI
    this.destroyed = false

    if (!editor || !editor.isAlive()) return

    this.editor = editor
    this.subscriptions = new CompositeDisposable()
    this.marker = this.editor.markBufferPosition(this.point)
    this.subscriptions.add(
      this.marker.onDidChange(({newHeadBufferPosition}) => {
        this.point = newHeadBufferPosition
      })
    )
    this.subscriptions.add(this.editor.onDidDestroy(() => this.unSubscribe()))
  }

  unSubscribe() {
    this.subscriptions.dispose()
    this.editor = this.subscriptions = null
  }

  destroy() {
    if (this.editor) this.unSubscribe()
    this.destroyed = true
    if (this.marker) this.marker.destroy()
    this.point = this.URI = this.marker = null
  }

  isDestroyed() {
    return this.destroyed
  }

  isValid() {
    if (this.isDestroyed()) return false
    if (
      atom.config.get("cursor-history.excludeClosedBuffer") &&
      !(this.editor && this.editor.isAlive())
    ) {
      return false
    }
    return existsSync(this.URI)
  }

  isAtSameRow(otherEntry) {
    return (
      otherEntry.point != null &&
      this.point != null &&
      otherEntry.point.row === this.point.row &&
      otherEntry.URI === this.URI
    )
  }

  inspect() {
    let s = `${this.point}, ${path.basename(this.URI)}`
    if (!this.isValid()) s += " [invalid]"
    return s
  }
}
