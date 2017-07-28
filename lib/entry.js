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
    this.marker = editor.markBufferPosition(point)
    this.subscriptions.add(
      this.marker.onDidChange(({newHeadBufferPosition}) => {
        this.point = newHeadBufferPosition
      })
    )
    this.subscriptions.add(
      editor.onDidDestroy(() => {
        if (editor.getURI()) {
          this.unSubscribe()
        } else {
          this.destroy()
        }
      })
    )
  }

  unSubscribe() {
    this.subscriptions.dispose()
    this.editor = this.subscriptions = null
  }

  // isAllowedisItemAllowed

  destroy() {
    if (this.destroyed) return

    if (this.editor) this.unSubscribe()
    this.destroyed = true
    if (this.marker) this.marker.destroy()
    this.point = this.URI = this.marker = null
  }

  isDestroyed() {
    return this.destroyed
  }

  isEditorAlive() {
    return this.editor && this.editor.isAlive()
  }

  isValid() {
    if (this.isDestroyed()) return false

    const excludeClosedBuffer = atom.config.get("cursor-history.excludeClosedBuffer")
    return this.isEditorAlive() || (!excludeClosedBuffer && existsSync(this.URI))
  }

  isSameFile(other) {
    return (this.editor && this.editor === other.editor) || (this.URI && (this.URI && other.URI))
  }

  isAtSameRow(other) {
    return (
      this.isSameFile(other) &&
      this.isValid() &&
      other.isValid() &&
      other.point.row === this.point.row &&
      other.URI === this.URI
    )
  }

  toString() {
    return `${this.point}, ${this.URI}`
  }

  inspect() {
    if (this.isDestroyed()) {
      return "[Destroyed]"
    } else {
      const invalid = this.isValid() ? "" : " [Invalid]"
      return `${this.point}, ${path.basename(this.URI)}` + invalid
    }
  }
}
