# Isogrid

Isogrid is a macOS menu bar app that keeps many windows visible at once in a grid. I built it to run several Claude Code windows, terminals and browsers side by side, and to switch between groups of them as one unit.

## Using it

Press ⌥G to open the layout picker. Type two digits for rows and columns (`24` is two rows of four), or pick a preset with the arrow keys and press Return. The visible windows on that display move into the grid, each into the free cell nearest to where it already was, so applying the same layout twice moves nothing.

Hold ⇧ while dragging a window by its title bar to show the grid, and release over a cell to drop the window there. Dropping onto a cell that already holds a window swaps the two. While you hover, a frosted copy of that window shows where it will go.

Drag the gap between two tiled windows to resize them. A plain drag resizes the two windows on either side of the pointer; with ⇧ held, it moves the whole line, every window whose edge lines up with that gap. A dragged gap snaps to other windows' edges and to even splits within 12 points, with a guide line and, on a Force Touch trackpad, the alignment click.

Every tiling saves its windows as a set in the next free slot, 1 to 9. ⌃⌥1 through ⌃⌥9 bring a set back to the front, restoring minimized windows and putting moved ones back in their cells. Focusing any window of a set, by clicking it, with ⌘Tab or from Mission Control, raises the rest of the set with it. ⌃⌥Space opens an overview with every set as one card. Sets name themselves after the apps in them, and closed windows drop out on their own.

The menu bar icon draws the current layout. Its menu holds the drag modifier and the spacing between windows. Grids, sets and spacing persist per display, and follow a monitor that macOS reconnects under a new ID.

The `isogrid://` scheme drives it from Raycast, Shortcuts or a shell:

```
open isogrid://layout/2x4   # set a layout and tile
open isogrid://tile         # tile again with the current layout
open isogrid://set/1        # bring set 1 forward
open isogrid://overview
open isogrid://dismiss      # close the picker or overview
```

## Building

Isogrid needs macOS 15 or later on Apple silicon and Swift 6.2 (Xcode 26, or its Command Line Tools). On macOS 26 the picker and drop target use Liquid Glass.

```
scripts/make-signing-identity.sh   # run once, creates a local signing identity
scripts/build.sh                   # writes build/Isogrid.app
open build/Isogrid.app
```

It needs Accessibility access to move other apps' windows, and asks for it on first launch. macOS ties that grant to the code signature, which is why `build.sh` signs with a stable local identity when one exists. Signed ad hoc, the grant is lost on every rebuild. Screen Recording is optional and only adds live previews to the overview.

## How it works

`IsogridCore` holds the parts that can be reasoned about without a screen, which are grid geometry, gap dragging and snapping, which window goes to which cell, swaps, and the set library. It has no AppKit dependency and is covered by unit tests.

The app target is AppKit with SwiftUI for the picker and overview, and runs on the main actor by default.

- `Windows/` reads windows through `CGWindowList`, which is cheap and needs no permission, and moves them through Accessibility. Accessibility calls are synchronous IPC into other apps, so moves run off the main thread, and each one is checked again after 80 and 220 ms because some apps apply a resize late.
- `Interaction/` holds the global shortcuts (Carbon hot keys, which need no Input Monitoring permission), the modifier drag, the gap drag (a `CGEvent` tap that claims clicks only inside a live gap), and group focus.
- `Interface/` draws the overlay, picker, overview and menu. Window moves happen behind a short frosted curtain with glass stand-ins flying to their cells, so apps redrawing mid-resize never show. Motion uses springs stepped on the display link and respects Reduce Motion.

Some behaviour exists because the obvious version failed in use:

- Group focus acts only on a focus that reads the same twice, 80 ms apart, because apps briefly report a stale focused window while you switch away.
- It never raises the window that just lost focus, so closing a set's window with ⌘W doesn't bring it back.
- It raises other apps' windows with a plain `AXRaise` and never activates their apps, which avoids flicker. Raising waits until activation has brought the clicked window to the front; anything raised earlier lands behind the window you came from.
- Full-screen panels are removed on a timer, never on an animation's completion, and Esc is a system-wide shortcut while the overview is open, so neither can stay on screen and swallow clicks.
- Isogrid uses one private function, `_AXUIElementGetWindow`, to map an Accessibility window to its window server ID. Rectangle and AltTab rely on it too.

## Testing

```
scripts/test.sh   # unit tests for IsogridCore
scripts/e2e.sh    # end-to-end, against real windows
```

`e2e.sh` opens throwaway windows from four helper processes for about 20 seconds and drives a separate, headless instance of Isogrid with its own settings, so your windows and sets are left alone. It checks real window positions and stacking order for tiling across apps, swapping by drop, group raise, closed windows staying closed, recall of minimized and moved windows, and gap drags and snapping with two sets on one display, and it checks that no panel is left on screen. Leave the Mac alone while it runs, because switching apps puts other windows in front and fails the stacking checks.

## Credits

Window moving follows techniques from [Rectangle](https://github.com/rxhanson/Rectangle); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Released under the [MIT License](LICENSE).
