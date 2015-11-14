## 0.5.9
* FIX: Warning from Atom v1.2.0

## 0.5.8
* FIX: When landing by prev/next commands, cursor position is not properly centered.
* Update supported engines to over v1.1.0

## 0.5.7
skip because of release mistaken.
0.5.8 was meant to be 0.5.7.

## 0.5.6
* Minor refactoring.
* [FIX deprecation warning] use Promise.then instead of done.

## 0.5.5 - Spec complete
* Add travis-CI
* More spec coverage, and cleanup.
* Change default flash duration from 200ms to 150ms

## 0.5.4 - Improve/Add spec
* Refactoring.
* Add ignoreCommands setting parameter.
* Add spec

## 0.5.3 - Improve
* Minor refactoring

## 0.5.2 - Improve
* Refactoring
* Minor bugfix
* Improve: efficient and safe removal of ivalid/destroyed entry.

## 0.5.1 - Improve
* Add delay to properly save symbols-view:go-to-declaration.
* Don't debounce for cursor-history command dispatch.

## 0.5.0 - Improve, completely rewritten
* now use atom.commands.onWillDispatch/onDidDispatch
  instead of onDidChangeCursorPosition
* No longer track renamed buffer, since its make things confuse
  It even tracked files which was removed and moved to system's trash folder.
* Now resilient for cursor position change happen internally in several commands.
* As a result no longer need workaround for symbols-view's cursor internal movement.
  Now work further well with symbols-view and other packages.
* [New command] to move to next/prev only within current active editor.

## 0.4.18 - FIX
* Don't throw error when executed on not-editor buffer(like project-find-result) #8

## 0.4.17 - FIX
* Not ideal way of fix, but need to avoid exception again. #7

## 0.4.16 - FIX
* Not ideal way of fix, but need to avoid exception #7

## 0.4.15 - Improve
* Remove unnecessary Flasher.flash arguments.
* Update readme to follow vim-mode's command-mode to normal-mode

## 0.4.14 - FIX
* Fix #5 TexEditor was not released immediately after destroyed. Thanks @aki77

## 0.4.13 - FIX
* Fix editor already destroyed in delayed execution.

## 0.4.12 - Improve
* Refactoring.
* Better integration with symbols-view #3
* Delaying unlock() to avoid unlocking while sequential `next`, `prev` jump.

## 0.4.11 - Improve
* Fix disposable() on TextEditor::destroy()

## 0.4.10 - Improve
* Fix #4 subscription leak each time editor destroyed
* Delete unused keymap

## 0.4.8 - Improve
* Use `atom-config-plus`.
* throttle saving to well fit to `symbols-view:go-to-declaration`
* Scrooll to center on target is not current paneItem.

## 0.4.7 - Fix deprecated API.
* Fix for atom/atom#6867

## 0.4.6 - Fix and Feature
* New option `excludeClosedBuffer` false by default.
* [Fix] `prev` should `Prev`. prev was not worked when back from head.

## 0.4.5 - Fix
* Debug mode not working since debug() is un-intentionally deleted

## 0.4.4 - Improve
* Now configurable `FlashType` from 'line', 'word', 'point'

## 0.4.3 - Fix deubug print.
* Flash cursor line on landing.
* Independent setgings object and utility functions.
* settings option ordered.
* Set cursor position to middle of screen if target was off-screen.

## 0.4.2 - Fix deubug print.

## 0.4.1 - Fix version info sorry..

## 0.4.0 - Improve
* Rewrite history::add() comment.
* add wrapper class `LastEditor` and `Entry` to handle corner case situation.
* greatly improve for internal structure and fix several bug.
* Configurable option to keep current pane on history excursion with `prev`, `next`.
* Update history entry on pathChange(`onDidChangePath`).
* More precise handling on ActivePaneItem and CursorMoved event.

## 0.2.10 - Improve 2015-05-10
* More Vim like history concatenation.

## 0.2.9 - Improve 2015-05-09
* Cleanup and misc bug fix.

## 0.2.8 - Improve 2015-05-08
* [FIX] calling History::dispose() throw Error when deactivated.

## 0.2.7 - Improve 2015-05-08
* Cleanup. and eliminate direct splice() to destroy() marker properly.

## 0.2.6 - Improve 2015-05-08
* [BUGFIX] Uncaught Error: This TextEditor has been destroyed #2

## 0.2.5 - Improve 2015-05-08
* No longer try to jump to mark on deleted file.

## 0.2.4 - Improve 2015-05-08
* Use Marker's setProperties rather than Object which own marker as property.

## 0.2.3 - Improve 2015-05-07
* Use `oldBufferPosition`.
* Add debug info.
* FIX corner case bug.

## 0.2.2 - Improve 2015-05-06
* No longer change active pane if editor's URI is same.
* Always save history when buffer URI changes.
* [BREAKING] rename `cursor-history:reset` to `cursor-history:clear`.

## 0.2.1 - Bugfix 2015-05-06
* @direction was set when entry return undefined.
* Now use Marker which is more resilient to buffer change.
* Rename filename from cursor-history.coffee to history.coffee
* [BUG FIX]: Ignore untitled buffer since have not URI or PATH.
* [BUG FIX]: History#index got negative on prev() on History#entries is empty.

## 0.2.0 - First Release 2015-05-06
* Refactoring
* Ignore when multiple cursor

## 0.1.0 - Start 2015-05-05
* Every feature added
* Every bug fixed
