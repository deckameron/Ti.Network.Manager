# Fix: random crash when opening the details screen (KrollBridge / pointer authentication failure)

## Problem

Intermittent, hard-to-reproduce crash when opening the details screen from an already-cached item. The error changed on every occurrence (`_UIPointerInteractionPencilHoverDriver`, `NSConcreteValue`, etc. receiving `boundBridge:withKrollObject:`), eventually culminating in an `EXC_BAD_ACCESS` with "pointer authentication failure" — a classic sign of memory corruption, not a defect in any specific object.

## Root cause

In `TNMRequestProxy.send()`, a cache hit (`cache-first`) called `handleCachedResponse()` **synchronously**, directly on the same call stack as the user's touch (`touchesEnded:withEvent:` → click handler → `request.send()`). This fired the `complete` event — and all the JS code it triggers, including opening a brand new window — **reentrantly, while UIKit was still processing the touch event**, before it had finished unwinding. That reentrancy corrupted memory, causing the crash with a different object class each time.

The normal network path was already asynchronous (`DispatchQueue.main.async`); only the cache shortcut skipped that protection.

Additionally, `TNMLogger` used a single static `DateFormatter` shared across threads — `DateFormatter` is not thread-safe for concurrent calls, and with multiple pooled `URLSession`s each running their own queue, this also caused a data race.

## Fixes

- **`TNMRequestProxy.swift`**: the cache hit path in `send()` now dispatches `handleCachedResponse()` via `DispatchQueue.main.async`, matching the network path. Same treatment applied to the `fireEvent("error", ...)` call for invalid URLs.
- **`TNMLogger.swift`**: all logging calls now go through a dedicated serial queue (`logQueue`), eliminating concurrent access to the shared `DateFormatter`.
- **`TNMRequestProxy.swift`** (related, earlier fix): `handleError()` now has the same `isActive` guard that `handleComplete()` already had, preventing a delayed/cancelled response from firing events after the request had already been resolved.

## How to test

1. Open a title (populates the cache).
2. Go back and open the **same title again** — this is the path that hits the cache directly.
3. Repeat a few times in a row, including rapid taps. Before the fix, this flow crashed the app frequently.
