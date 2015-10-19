# cursor-history [![Build Status](https://travis-ci.org/t9md/atom-cursor-history.svg)](https://travis-ci.org/t9md/atom-cursor-history)

Like browser's Go and Back button, like `ctrl-i`, `ctrl-o` in Vim.
You can go/back to cursor position history.

![gif](https://raw.githubusercontent.com/t9md/t9md/3d4a0bd38ac9571510d5ba52aa5361897b123218/img/atom-cursor-history.gif)

# Keymap

No default keymap. You need to set by yourself.  

* e.g.

```coffeescript
'atom-workspace':
  'ctrl-i':     'cursor-history:next'
  'ctrl-o':     'cursor-history:prev'
  'ctrl-cmd-i': 'cursor-history:next-within-editor'
  'ctrl-cmd-o': 'cursor-history:prev-within-editor'
```

# Commands

* `cursor-history:next`: Go to next point in history.
* `cursor-history:prev`: Go to previous point in history.
* `cursor-history:next-within-editor`: Go to next point in history within current editor.
* `cursor-history:prev-within-editor`: Go to previous point in history within current editor.
* `cursor-history:clear`: Clear history.

# Features

* Go and Back to prev/next position of cursor history including closed buffer(can exclude closed buffer with config option).
* Flash cursor line on land. Can disable, customize flash color, duration and type(line, word, point).
* Vim like history concatnation(Never save same line per file. This allow you to jump specific line only once).
* Auto adjust cursor position to middle of screen if target was off-screen.

# When cursor history saved?

* when editor lost focus.
* when cursor position's row delta exceeds rows specified by `rowDeltaToRemember`(default 4).

# TODO
- [x] Spec
- [x] Don't use editor.onDidChangeCursorPosition, use atom.commands.onDidDispatch instead.
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
