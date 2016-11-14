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

- `cursor-history:next`: Go to next point in history.
- `cursor-history:prev`: Go to previous point in history.
- `cursor-history:next-within-editor`: Go to next point in history within current editor.
- `cursor-history:prev-within-editor`: Go to previous point in history within current editor.
- `cursor-history:clear`: Clear history.

# Features

- Go and Back to previous/next position of cursor history including closed buffer(can exclude closed buffer with config option).
- Flash cursor line on land.
- Vim like history concatenation (Never save same line per file. This allow you to jump specific line only once).

# When cursor history saved?

- When editor lost focus.
- When cursor moved and row delta exceeds `rowDeltaToRemember`(default 4).
- When cursor moved within same row and column delta exceeds `columnDeltaToRemember`(default 9999).

# Customize flashing effects.

When you enabled `flashOnLand`(default `false`), it flashes cursor line when move around history position.  
You can customize flashing effect in your `style.less` based on following example.  

```less
@keyframes cursor-history-flash {
  from { background-color: red; }
}
atom-text-editor.editor .line.cursor-history-flash-line {
  animation-duration: 1s;
}
```
