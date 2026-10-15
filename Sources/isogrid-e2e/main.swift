import AppKit
import IsogridCore

// End-to-end test. It drives a separate `Isogrid --e2e` instance against fixture windows and
// checks real window positions and stacking order. Run through scripts/e2e.sh.
// Usage: isogrid-e2e <path to Isogrid.app> <path to IsogridFixture>

let appPath = CommandLine.arguments[1]
let fixturePath = CommandLine.arguments[2]
let center = DistributedNotificationCenter.default()
var replies: [String: [AnyHashable: Any]] = [:]
var fixtures: [String: (pid: pid_t, windows: [CGWindowID])] = [:]
var failures = 0
var counter = 0

center.addObserver(forName: Notification.Name("dev.isogrid.e2e.reply"), object: nil, queue: nil) { note in
    let info = note.userInfo ?? [:]
    replies[info["id"] as? String ?? ""] = info
}
center.addObserver(forName: Notification.Name("dev.isogrid.fixture.ready"), object: nil, queue: nil) { note in
    let info = note.userInfo ?? [:]
    let windows = (info["windows"] as? [Int] ?? []).map { CGWindowID($0) }
    fixtures[info["name"] as? String ?? ""] = (pid_t(info["pid"] as? Int ?? 0), windows)
}

// MARK: Helpers

@discardableResult
func spin(timeout: TimeInterval, until condition: () -> Bool = { false }) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !condition(), Date() < end {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

func check(_ condition: Bool, _ message: String) {
    print(condition ? "  ✔ \(message)" : "  ✘ \(message)")
    if !condition { failures += 1 }
}

@discardableResult
func send(_ command: String, _ extra: [String: Any] = [:], timeout: TimeInterval = 6) -> [AnyHashable: Any]? {
    counter += 1
    let id = "c\(counter)"
    var info = extra
    info["id"] = id
    info["command"] = command
    center.postNotificationName(Notification.Name("dev.isogrid.e2e.command"), object: nil, userInfo: info, deliverImmediately: true)
    guard spin(timeout: timeout, until: { replies[id] != nil }) else {
        check(false, "Isogrid answered \(command)")
        return nil
    }
    if replies[id]?["ok"] as? Bool != true {
        check(false, "\(command) failed: \(replies[id]?["detail"] as? String ?? "")")
    }
    return replies[id]
}

func fixture(_ name: String, _ command: String, _ extra: [String: Any] = [:]) {
    var info = extra
    info["command"] = command
    center.postNotificationName(Notification.Name("dev.isogrid.fixture.\(name)"), object: nil, userInfo: info, deliverImmediately: true)
}

func window(_ name: String, _ index: Int) -> CGWindowID { fixtures[name]!.windows[index] }

/// On-screen normal windows, front-most first.
func stack() -> [(id: CGWindowID, owner: String, bounds: CGRect)] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { entry in
        guard entry[kCGWindowLayer as String] as? Int == 0,
              let id = entry[kCGWindowNumber as String] as? Int,
              let raw = entry[kCGWindowBounds as String], let bounds = CGRect(dictionaryRepresentation: raw as! CFDictionary) else { return nil }
        return (CGWindowID(id), entry[kCGWindowOwnerName as String] as? String ?? "", bounds)
    }
}

func bounds(_ id: CGWindowID) -> CGRect? { stack().first { $0.id == id }?.bounds }
func isOnScreen(_ id: CGWindowID) -> Bool { bounds(id) != nil }

func index(_ id: CGWindowID) -> Int { stack().firstIndex { $0.id == id } ?? Int.max }

/// Counts full-screen Isogrid panels of any level on any display, which must never be left behind.
func leftoverPanels() -> Int {
    let widths = NSScreen.screens.map(\.frame.width)
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.filter { entry in
        guard entry[kCGWindowOwnerName as String] as? String == "Isogrid",
              let raw = entry[kCGWindowBounds as String], let bounds = CGRect(dictionaryRepresentation: raw as! CFDictionary) else { return false }
        return widths.contains { abs(bounds.width - $0) < 1 }
    }.count
}

func dumpOrder() {
    let names = Dictionary(uniqueKeysWithValues: fixtures.flatMap { name, value in value.windows.enumerated().map { ($1, "\(name)\($0)") } })
    print("    order: " + stack().prefix(8).map { names[$0.id] ?? $0.owner }.joined(separator: " > "))
}

func close(_ a: CGRect?, _ b: CGRect) -> Bool {
    guard let a else { return false }
    return abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
}

func launch(_ path: String, _ arguments: [String]) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    try! process.run()
    return process
}

// MARK: Setup

let screen = NSScreen.screens[0]
let primaryHeight = screen.frame.height
let visible = screen.visibleFrame
let area = CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
let cells = TileLayout(rows: 2, columns: 2)!.cellFrames(in: area, gap: 8)

print("Starting fixtures and a test instance of Isogrid")
let fixtureProcesses = [launch(fixturePath, ["A", "3"]), launch(fixturePath, ["B", "1"]), launch(fixturePath, ["C", "1"]),
                        launch(fixturePath, ["D", "2"])]
let isogrid = launch("/usr/bin/open", ["-n", "-a", appPath, "--args", "--e2e"])
guard spin(timeout: 15, until: { fixtures.count == 4 && replies["ready"] != nil }) else {
    print("  ✘ setup timed out (fixtures: \(fixtures.keys.sorted()), isogrid ready: \(replies["ready"] != nil))")
    fixtureProcesses.forEach { $0.terminate() }
    exit(1)
}
let a = fixtures["A"]!.pid, b = fixtures["B"]!.pid, c = fixtures["C"]!.pid
let members = [window("A", 0), window("A", 1), window("A", 2), window("B", 0)]
let cover = window("C", 0)

func focus(_ id: CGWindowID, _ pid: pid_t) {
    send("focus", ["window": Int(id), "pid": Int(pid)])
}

func membersAboveCover(_ ids: [CGWindowID]) -> Bool {
    let coverIndex = index(cover)
    let ok = ids.allSatisfy { index($0) < coverIndex }
    if !ok {
        let names = Dictionary(uniqueKeysWithValues: fixtures.flatMap { name, value in value.windows.enumerated().map { ($1, "\(name)\($0)") } })
        print("    order: " + stack().prefix(8).map { names[$0.id] ?? $0.owner }.joined(separator: " > "))
    }
    return ok
}

// MARK: Tests

print("Tile 2×2 across two apps")
send("tile", ["layout": "2x2", "pids": [Int(a), Int(b)]])
spin(timeout: 0.4)
let landed = members.map { id in cells.firstIndex { close(bounds(id), $0) } }
check(landed.allSatisfy { $0 != nil } && Set(landed.compactMap { $0 }).count == 4, "every window fills its own cell \(landed)")
check(leftoverPanels() == 0, "no panel left after tiling")
let sets = send("sets")?["detail"] as? String ?? ""
check(sets.hasPrefix("1:") && members.allSatisfy { sets.contains(String($0)) }, "the tiled windows form set 1 (\(sets))")

print("Dropping a window on an occupied cell swaps the two")
if let from = landed[0], let to = landed[3] {
    send("drop", ["window": Int(window("A", 0)), "slot": to])
    spin(timeout: 0.4)
    check(close(bounds(window("A", 0)), cells[to]), "the dropped window takes the target cell")
    check(close(bounds(window("B", 0)), cells[from]), "the window that was there moves to the dropped window's old cell")
    let after = members.map { id in cells.firstIndex { close(bounds(id), $0) } }
    check(Set(after.compactMap { $0 }).count == 4, "no cell is left empty \(after)")
    // Swap back so the rest of the test sees the original layout.
    send("drop", ["window": Int(window("A", 0)), "slot": from])
    spin(timeout: 0.4)
    check(close(bounds(window("A", 0)), cells[from]) && close(bounds(window("B", 0)), cells[to]), "swapping back restores both")
}

print("Focusing a member brings the whole set forward")
fixture("C", "frame", ["frame": [Double(area.minX), Double(area.minY), Double(area.width), Double(area.height)]])
spin(timeout: 0.3)
focus(cover, c)
spin(timeout: 0.6)
check(stack().first?.id == cover, "a covering window from another app is in front")
focus(window("A", 0), a)
spin(timeout: 0.9)
check(stack().first?.id == window("A", 0), "the focused member is in front")
check(membersAboveCover(members), "every member is above the covering window")
check(NSWorkspace.shared.frontmostApplication?.processIdentifier == a, "focus stayed on the clicked window's app")

print("Closing a member doesn't bring it back")
// Close the window you're in, as you would with ⌘W; focus passes to a sibling in the set
// while the closed window is still fading out.
focus(cover, c)
spin(timeout: 0.5)
focus(window("A", 2), a)
spin(timeout: 0.6)
fixture("A", "close", ["index": 2])
spin(timeout: 1.0)
check(!isOnScreen(window("A", 2)), "the closed window stays closed")

print("Moving between members of a covered set raises the set")
focus(window("A", 0), a)
spin(timeout: 0.6)
fixture("C", "frame", ["frame": [Double(area.minX), Double(area.minY), Double(area.width), Double(area.height)]])
focus(cover, c)
spin(timeout: 0.5)
// Back into the set on a different member than before, like picking it in Mission Control.
focus(window("B", 0), b)
spin(timeout: 0.9)
check(stack().first?.id == window("B", 0), "the picked member is in front")
check(membersAboveCover([window("A", 0), window("A", 1), window("B", 0)]), "the rest of the set came with it")
focus(cover, c)
spin(timeout: 0.5)
focus(window("A", 0), a)
spin(timeout: 0.9)
check(!isOnScreen(window("A", 2)), "raising the set again doesn't revive it")
check(membersAboveCover([window("A", 0), window("A", 1), window("B", 0)]), "the remaining members are above the cover")

print("Recall restores minimized and moved members")
fixture("A", "minimize", ["index": 1])
fixture("B", "frame", ["frame": [300, 300, 500, 320]])
spin(timeout: 1.2)
focus(cover, c)
spin(timeout: 0.5)
send("recall", ["slot": 1])
spin(timeout: 0.6)
check(close(bounds(window("A", 1)), cells[landed[1] ?? 0]), "the minimized member is back in its cell")
check(close(bounds(window("B", 0)), cells[landed[3] ?? 0]), "the moved member is back in its cell")
check(!isOnScreen(window("A", 2)), "the closed member isn't revived")
check(membersAboveCover([window("A", 0), window("A", 1), window("B", 0)]), "the set is above the cover")
let frontIsMember = [window("A", 0), window("A", 1), window("B", 0)].contains(stack().first?.id ?? 0)
if !frontIsMember { dumpOrder() }
check(frontIsMember, "a member of the set is the front window")
check(leftoverPanels() == 0, "no panel left after recall")

print("Overview opens and always goes away")
send("overview")
spin(timeout: 0.4)
check(leftoverPanels() == 1, "the overview is on screen")
send("dismiss")
spin(timeout: 0.5)
check(leftoverPanels() == 0, "dismissing removes it")
focus(cover, c)
spin(timeout: 0.5)
send("overview")
spin(timeout: 0.4)
send("pick", ["slot": 1])
spin(timeout: 0.7)
check(leftoverPanels() == 0, "picking a set removes it")
check(membersAboveCover([window("A", 0), window("A", 1), window("B", 0)]), "picking brings the set forward")

print("A gap drag uses the grid of the set you're in, and snaps into line")
let d = fixtures["D"]!.pid
send("tile", ["layout": "1x2", "pids": [Int(d)]])
spin(timeout: 0.4)
let others = [window("D", 0), window("D", 1)]
let othersBefore = others.map(bounds)
check(others.allSatisfy { isOnScreen($0) }, "a second set with a different layout sits on the same display")
focus(cover, c)
spin(timeout: 0.5)
focus(window("A", 0), a)
spin(timeout: 0.9)

let remaining = [window("A", 0), window("A", 1), window("B", 0)]
func occupant(_ cell: Int) -> CGWindowID? { remaining.first { close(bounds($0), cells[cell]) } }
// The row with the most windows gets dragged; the other row is used for the snap.
func windowsInRow(_ row: Int) -> Int { [occupant(row * 2), occupant(row * 2 + 1)].compactMap { $0 }.count }
let dragRow = windowsInRow(0) >= windowsInRow(1) ? 0 : 1
let snapRow = 1 - dragRow
let gapX = (cells[0].maxX + cells[1].minX) / 2
let before = remaining.map(bounds)
send("gap", ["points": [Double(gapX), Double(cells[dragRow * 2].midY), Double(gapX + 120), Double(cells[dragRow * 2].midY)]])
spin(timeout: 0.4)
if let left = occupant(dragRow * 2) ?? before.indices.first(where: { close(before[$0], cells[dragRow * 2]) }).map({ remaining[$0] }) {
    check(abs((bounds(left)?.width ?? 0) - (cells[dragRow * 2].width + 120)) <= 2, "the left window in the dragged row grew by the drag")
}
for (id, old) in zip(remaining, before) where old.map({ abs($0.midY - cells[snapRow * 2].midY) < 2 }) ?? false {
    check(close(bounds(id), old!), "windows in the other row stayed put")
}
check(zip(others, othersBefore).allSatisfy { close(bounds($0), $1!) }, "the other set's windows weren't touched")

// Drag the other row's gap to 6 points past the moved edge, where it should snap exactly onto it.
let movedEdge = cells[0].maxX + 120 + 4
send("gap", ["points": [Double(gapX), Double(cells[snapRow * 2].midY), Double(movedEdge + 6), Double(cells[snapRow * 2].midY)]])
spin(timeout: 0.4)
let dragLeft = remaining.first { abs((bounds($0)?.midY ?? 0) - cells[dragRow * 2].midY) < 2 && (bounds($0)?.minX ?? 9999) < gapX }
let snapLeft = remaining.first { abs((bounds($0)?.midY ?? 0) - cells[snapRow * 2].midY) < 2 && (bounds($0)?.minX ?? 9999) < gapX }
let snapRight = remaining.first { abs((bounds($0)?.midY ?? 0) - cells[snapRow * 2].midY) < 2 && (bounds($0)?.minX ?? 0) > gapX }
if let dragLeft, let edge = bounds(dragLeft)?.maxX {
    if let snapLeft { check(abs((bounds(snapLeft)?.maxX ?? 0) - edge) <= 1, "the other row's gap snapped into line with the dragged one") }
    else if let snapRight { check(abs((bounds(snapRight)?.minX ?? 0) - (edge + 8)) <= 1, "the other row's gap snapped into line with the dragged one") }
}
check(zip(others, othersBefore).allSatisfy { close(bounds($0), $1!) }, "the other set's windows still weren't touched")
check(leftoverPanels() == 0, "no panel left after gap drags")

// MARK: Teardown

send("quit", timeout: 2)
for name in ["A", "B", "C", "D"] { fixture(name, "quit") }
spin(timeout: 0.8)
fixtureProcesses.forEach { if $0.isRunning { $0.terminate() } }
_ = isogrid
print(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
