# cursor-history

Jump to next and previous cursor position by remembering cursor position history.

# Features

* Flash cursor line on land(configurable, disable this feature, or customize color and duration).
* Can jump to prev/next point even if Buffer is already destroyed.
* Aware file renaming.
* Vim like history concatnation(never keep multiple position which have same line in same file, this allow you to jump only once for specific line within one file).

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
'atom-text-editor.vim-mode.command-mode':
  'ctrl-i': 'cursor-history:next'
  'ctrl-o': 'cursor-history:prev'
```

# How to use

Use following command or set Keymap.
* `cursor-history:next`: Go to next     point in history.
* `cursor-history:prev`: Go to previous point in history.
* `cursor-history:clear`: Clear history when you are in trouble.

# What condition cursor history will be kept?

* At another file opened(ActiveTextEditor's `getURI()` changed)
* When the row delata between old cursor position and new exceeds `rowDeltaToRemember`(default 4).  

# TODO
- [?] Ensure not open unexisting file.
- [x] Flash cursor position cause scroll.
- [ ] Adjust cursor position after jump to middle of screen.
- [ ] Support serialization to support per-project cursor history.
- [ ] Make configurable when history is saved.
- [x] Configurable option to keep current pane on history excursion with `prev`, `next`.
- [x] Update history entry on pathChange(`onDidChangePath`).
- [x] Won't save history when multiple cursor is used.
- [x] Use oldBufferPosition rather than newBufferPosition to save.
- [x] Exclude inValid Marker. deleted File(URI).
- [x] Better history concatenation.
- [x] Use Maker instead of buffer position.
- [x] More precise handling when active TextEditor change
