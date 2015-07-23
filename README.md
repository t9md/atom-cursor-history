# cursor-history

Jump to next and previous cursor position by keeping track of cursor position.

![gif](https://raw.githubusercontent.com/t9md/t9md/8b86b09ff01f3dbb45324119cfd41c39f16b115e/img/atom-cursor-history.gif)

# Features

* Flash cursor line on land. Can disable or customize flash color, duration and type(line, word, point).
* Can jump to prev/next point of closed Buffer(can configure exclude closed).
* Aware file renaming.
* Vim like history concatnation(Never save same line per file. This allow you to jump specific line only once).
* Auto adjust cursor position to middle of screen if target was off-screen.
* Save cursor history on only symbols-views shown, hidden.

# Keymap

No keymap by default.

* e.g.

```coffeescript
'atom-workspace':
  'ctrl-i': 'cursor-history:next'
  'ctrl-o': 'cursor-history:prev'
```

* if you use [vim-mode](https://atom.io/packages/vim-mode)

```coffeescript
'atom-text-editor.vim-mode.normal-mode':
  'ctrl-i': 'cursor-history:next'
  'ctrl-o': 'cursor-history:prev'
  # or
  ']': 'cursor-history:next'
  '[': 'cursor-history:prev'
```

# How to use

Use following command or set Keymap.
* `cursor-history:next`: Go to next point in history.
* `cursor-history:prev`: Go to previous point in history.
* `cursor-history:clear`: Clear history.

# What condition cursor history will be kept?

On following event, old cursor position is saved to history.
* When another file opened(ActiveTextEditor's `getURI()` changed)
* When the row delta between old and new cursor position exceeds `rowDeltaToRemember`(default 4).  
* When [symbols-view](https://github.com/atom/symbols-view) jump finished.

# TODO
- [ ] Support serialization to support per-project cursor history.
- [x] Configuration option to exclude closed buffer.
- [x] Ensure not open un-existing file.
- [x] Flash cursor line when target is off-screen.
- [x] Adjust cursor position after jump to middle of screen.
- [x] Configurable option to keep current pane on history excursion with `prev`, `next`.
- [x] Update history entry on file rename(`onDidChangePath`).
- [x] Don't save history when multiple cursors.
- [x] Use oldBufferPosition rather than newBufferPosition to save.
- [x] Exclude inValid Marker. deleted File(URI).
- [x] Better history concatenation(Vim-like).
- [x] Use Marker if I can, use Point for destroyed editor to avoid error.
- [x] Save history on ActiveTextEditor change.
- [x] Better integration with symbols-view's FileView, ProjectView.
- [x] Better integration with symbols-view's GoToView, GoBackView
