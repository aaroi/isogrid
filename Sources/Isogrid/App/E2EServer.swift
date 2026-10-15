import AppKit
import IsogridCore

/// Command channel for the end-to-end test (`scripts/e2e.sh`). Only active when Isogrid is
/// launched with `--e2e`; that instance acts on the test's fixture windows alone.
final class E2EServer {
    nonisolated static let commandName = Notification.Name("dev.isogrid.e2e.command")
    nonisolated static let replyName = Notification.Name("dev.isogrid.e2e.reply")
    nonisolated static let suiteName = "dev.isogrid.e2e"
    static let isEnabled = CommandLine.arguments.contains("--e2e")

    private let tiler: Tiler
    private let overview: OverviewController
    private let overlay: Overlay
    private let gaps: GapController
    private let center = DistributedNotificationCenter.default()

    init(tiler: Tiler, overview: OverviewController, overlay: Overlay, gaps: GapController) {
        self.gaps = gaps
        self.tiler = tiler
        self.overview = overview
        self.overlay = overlay
    }

    func start() {
        center.addObserver(forName: Self.commandName, object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            let id = info["id"] as? String ?? ""
            let command = info["command"] as? String ?? ""
            let pids = (info["pids"] as? [Int] ?? []).map { pid_t($0) }
            let layout = info["layout"] as? String
            let slot = info["slot"] as? Int
            let window = (info["window"] as? Int).map { CGWindowID($0) }
            let pid = (info["pid"] as? Int).map { pid_t($0) }
            let points = info["points"] as? [Double] ?? []
            let line = info["line"] as? Bool ?? false
            MainActor.assumeIsolated {
                self.run(command, id: id, pids: pids, layout: layout, slot: slot, window: window, pid: pid, points: points, line: line)
            }
        }
        reply(id: "ready", ok: true)
    }

    private func run(_ command: String, id: String, pids: [pid_t], layout: String?, slot: Int?, window: CGWindowID?, pid: pid_t?,
                     points: [Double], line: Bool) {
        guard let screen = NSScreen.screens.first else { return reply(id: id, ok: false, detail: "no screen") }
        Task {
            switch command {
            case "tile":
                guard let layout = layout.flatMap(TileLayout.init) else { return reply(id: id, ok: false, detail: "bad layout") }
                tiler.onlyPIDs = Set(pids)
                tiler.apply(layout, on: screen)
                await tiler.idle()
            case "recall":
                tiler.recall(slot: slot ?? 1)
                await tiler.idle()
            case "focus":
                // Focus the way Mission Control or a click does, by activating the app and making the window main.
                guard let window, let pid, let target = AXWindow.find(window, pid: pid) else {
                    return reply(id: id, ok: false, detail: "window not found")
                }
                target.focus()
            case "overview":
                overview.open()
            case "pick":
                overview.pick(slot ?? 1)
                await tiler.idle()
            case "dismiss":
                overview.close()
            case "drop":
                // A modifier-drag drop without the mouse, using the same survey and swap as a real drop.
                guard let window, let info = WindowList.info(for: window), let slot else {
                    return reply(id: id, ok: false, detail: "window not found")
                }
                let cells = Settings.shared.grid(for: screen).cellFrames(in: screen.axVisibleFrame, gap: Settings.shared.gap)
                let (origin, occupants) = DragController.survey(cells, dragging: info, on: screen)
                await withCheckedContinuation { continuation in
                    DragController.drop(info, origin: origin, into: slot, occupants: occupants, cells: cells, on: screen,
                                        overlay: overlay) { continuation.resume() }
                }
            case "gap":
                // A gap drag from (x0, y0) to (x1, y1), without the mouse.
                guard points.count == 4 else { return reply(id: id, ok: false, detail: "need 4 coordinates") }
                let started = await gaps.simulate(from: CGPoint(x: points[0], y: points[1]), to: CGPoint(x: points[2], y: points[3]), line: line)
                guard started else { return reply(id: id, ok: false, detail: "no live gap there") }
            case "sets":
                let sets = Settings.shared.library.sets.sorted { $0.slot < $1.slot }
                    .map { "\($0.slot):" + $0.members.map { String($0.windowID) }.joined(separator: ",") }
                return reply(id: id, ok: true, detail: sets.joined(separator: " "))
            case "quit":
                reply(id: id, ok: true)
                NSApp.terminate(nil)
                return
            default:
                return reply(id: id, ok: false, detail: "unknown command \(command)")
            }
            reply(id: id, ok: true)
        }
    }

    private func reply(id: String, ok: Bool, detail: String = "") {
        center.postNotificationName(Self.replyName, object: nil,
                                    userInfo: ["id": id, "ok": ok, "detail": detail], deliverImmediately: true)
    }
}
