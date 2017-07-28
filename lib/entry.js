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

  destroy() {
    if (this.destroyed) return

    if (this.editor) this.unSubscribe()
    this.destroyed = true
    if (this.marker) this.marker.destroy()
    this.point = this.URI = this.marker = null
  }

  isValid() {
    if (this.destroyed) return false

    const editorIsAlive = this.editor && this.editor.isAlive()

    if (atom.config.get("cursor-history.excludeClosedBuffer")) {
      return editorIsAlive
    } else {
      return editorIsAlive || (this.URI && existsSync(this.URI))
    }
  }

  isAtSameRow(other) {
    return (
      ((this.URI && this.URI === other.URI) || (this.editor && this.editor === other.editor)) &&
      (this.isValid() && other.isValid()) &&
      other.point.row === this.point.row &&
      other.URI === this.URI
    )
  }

  toString() {
    return `${this.point}, ${this.URI}`
  }

  inspect() {
    if (this.destroyed) {
      return "[Destroyed]"
    } else {
      const invalid = this.isValid() ? "" : " [Invalid]"
      return `${this.point}, ${path.basename(this.URI)}` + invalid
    }
  }
}
