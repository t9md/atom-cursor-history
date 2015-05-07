# cursor-history

Jump to next and previous cursor position by remembering cursor position history.

# Features

* Won't keep history when multiple cursor is used.

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

Currently when the row delata between old cursor position and new exceeds `rowDeltaToRemember`.  
I have some idea to make this more granular way.

# TODO
- [x] IMPORTANT: User oldBufferPosition rather than newBufferPosition to save. This need drastic data model(history) change, but must do.
- [ ] exclude inValid Mark. deleted File(URI).
- [x] Better history concatenation.
- [x] Use Maker instead of buffer position.
- [ ] Support serialization to support per-project cursor history.
- [x] More precise handling when active TextEditor change
- [ ] Make configurable when history is saved.
