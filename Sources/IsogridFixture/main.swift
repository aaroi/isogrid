import AppKit

// Throwaway windows for the end-to-end test. Run as `IsogridFixture <name> <count>`; listens on
// the distributed notification "dev.isogrid.fixture.<name>" for close, minimize, frame, minimum
// and steps.

let arguments = CommandLine.arguments
let name = arguments.count > 1 ? arguments[1] : "A"
let count = arguments.count > 2 ? Int(arguments[2]) ?? 2 : 2
let colors: [NSColor] = [.systemTeal, .systemIndigo, .systemOrange, .systemPink, .systemGreen, .systemPurple]

let app = NSApplication.shared
app.setActivationPolicy(.regular)

var windows: [NSWindow] = []
for i in 0..<count {
    let window = NSWindow(contentRect: NSRect(x: 160 + i * 70, y: 220 + i * 50, width: 560, height: 400),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Isogrid test \(name)\(i)"
    window.isReleasedWhenClosed = false
    window.backgroundColor = colors[(i + (name == "A" ? 0 : 3)) % colors.count]
    window.orderFrontRegardless()
    windows.append(window)
}

let center = DistributedNotificationCenter.default()
center.addObserver(forName: Notification.Name("dev.isogrid.fixture.\(name)"), object: nil, queue: .main) { note in
    let command = note.userInfo?["command"] as? String ?? ""
    let index = note.userInfo?["index"] as? Int ?? 0
    let frame = note.userInfo?["frame"] as? [Double] ?? []
    let size = note.userInfo?["size"] as? [Double] ?? []
    MainActor.assumeIsolated {
        guard windows.indices.contains(index) else { return }
        let window = windows[index]
        switch command {
        case "close": window.close()
        case "minimize": window.miniaturize(nil)
        case "frame" where frame.count == 4:
            // Top-left screen coordinates, like the rest of Isogrid.
            let height = NSScreen.screens.first?.frame.height ?? 0
            window.setFrame(NSRect(x: frame[0], y: height - frame[1] - frame[3], width: frame[2], height: frame[3]), display: true)
        case "minimum" where size.count == 2:
            window.minSize = NSSize(width: size[0], height: size[1])
        case "steps" where size.count == 2:
            // Sizes in whole steps, the way terminals size to whole characters.
            window.contentResizeIncrements = NSSize(width: size[0], height: size[1])
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    let ids = windows.map(\.windowNumber)
    center.postNotificationName(Notification.Name("dev.isogrid.fixture.ready"), object: nil,
                                userInfo: ["name": name, "pid": Int(ProcessInfo.processInfo.processIdentifier), "windows": ids],
                                deliverImmediately: true)
}
app.run()
