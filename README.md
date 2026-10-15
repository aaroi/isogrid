# Isogrid

A macOS menu bar app that keeps many windows visible at once in a grid. Built for running several Claude Code windows, terminals and browsers side by side.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌥G | Pick a layout. Type rows then columns (`24` is 2×4), or use the arrows and Return. |
| ⇧ + drag a window | Show the grid and drop the window into a cell. Dropping on a taken cell swaps the two. |
| Drag a gap | Resize the two windows beside it. Hold ⇧ to move the whole line. |
| ⌃⌥1 to ⌃⌥9 | Bring a set back to the front. |
| ⌃⌥Space | Overview of all sets. |

## Sets

- Every tiling saves its windows as a set, in slots 1 to 9.
- Focusing any window of a set raises the rest with it, including from ⌘Tab and Mission Control.
- Recalling a set restores minimized windows and moves stray ones back to their cells.
- Sets name themselves after their apps. Closed windows drop out.

## Details

- Applying a layout moves each window to the free cell nearest to it, so applying it twice moves nothing.
- Dragged gaps snap to other edges and even splits within 12 pt.
- Grids, sets and spacing are saved per display, and survive a monitor reconnecting under a new ID.
- The menu bar icon draws the current layout. Its menu sets the drag modifier and window spacing.

Automate it with the `isogrid://` scheme:

```
open isogrid://layout/2x4   # set a layout and tile
open isogrid://tile         # tile again
open isogrid://set/1        # bring set 1 forward
open isogrid://overview
open isogrid://dismiss      # close the picker or overview
```

## Build

Requires macOS 15+ on Apple silicon and Swift 6.2 (Xcode 26 or its Command Line Tools).

```
scripts/make-signing-identity.sh   # run once
scripts/build.sh                   # writes build/Isogrid.app
open build/Isogrid.app
```

- **Accessibility** is required to move windows. macOS ties the grant to the code signature, so the build signs with a stable local identity to keep it across rebuilds.
- **Screen Recording** is optional and only adds live previews to the overview.

## Test

```
scripts/test.sh   # unit tests
scripts/e2e.sh    # end-to-end against real windows, about 20 s
```

The end-to-end test opens throwaway windows and drives a separate headless instance with its own settings, so your windows and sets are untouched. Leave the Mac alone while it runs.

## Structure

| Path | Contents |
| --- | --- |
| `Sources/IsogridCore` | Grid geometry, gap dragging, snapping, swaps and the set library. No AppKit, fully unit tested. |
| `Sources/Isogrid/Windows` | Reading windows (`CGWindowList`) and moving them (Accessibility, off the main thread). |
| `Sources/Isogrid/Interaction` | Shortcuts, modifier drag, gap drag and group focus. |
| `Sources/Isogrid/Interface` | Overlay, picker, overview and menu. |
| `Sources/Isogrid/App` | Entry point, settings, tiling and the end-to-end test channel. |

## Design notes

Each of these came from a failure in real use:

- Moves are rechecked after 80 and 220 ms, because some apps apply a resize late.
- Group focus only acts on focus that reads the same twice, 80 ms apart. Apps briefly report a stale window while you switch.
- The window that just lost focus is never raised, so closing one with ⌘W doesn't bring it back.
- Other apps' windows are raised without activating those apps, which avoids flicker.
- Full-screen panels close on a timer, never on an animation callback, so they can't get stuck over your screen.
- One private API is used, `_AXUIElementGetWindow`, the same one Rectangle and AltTab use.

## Credits

Window moving follows techniques from [Rectangle](https://github.com/rxhanson/Rectangle), see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). MIT licensed, see [LICENSE](LICENSE).
