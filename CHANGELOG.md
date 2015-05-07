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
