import AppKit
import Carbon.HIToolbox
import IsogridCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = Overlay()
    private let groups = GroupFocus()
    private lazy var tiler = Tiler(overlay: overlay, groups: groups)
    private lazy var picker = PickerController(overlay: overlay, tiler: tiler)
    private lazy var overview = OverviewController(tiler: tiler)
    private lazy var drag = DragController(overlay: overlay)
    private lazy var gaps = GapController(overlay: overlay)
    private var status: StatusItem?
    private var hotKeys: [HotKey] = []
    private var trustTimer: Timer?
    private var e2e: E2EServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        groups.start()
        Settings.shared.onLibraryAppsChange = { [weak self] in self?.groups.refreshObservers() }

        if E2EServer.isEnabled {
            // A second, headless instance driven by scripts/e2e.sh. It has no menu icon, shortcuts
            // or drag handling, so it can't interfere with the Isogrid you're using.
            e2e = E2EServer(tiler: tiler, overview: overview, overlay: overlay, gaps: gaps)
            e2e?.start()
            return
        }

        Settings.shared.reconcileDisplays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                NSScreen.forgetKeys()
                Settings.shared.reconcileDisplays()
            }
        }

        let status = StatusItem(picker: picker, overview: overview, tiler: tiler)
        self.status = status
        picker.onLayoutChange = { [weak status] in status?.refresh() }
        registerShortcuts()
        drag.start()
        startWhenTrusted()
    }

    /// Option-G opens the picker, Control-Option-Space the overview, Control-Option-1 to 9
    /// recall sets. Option with a digit is left alone because many layouts type @, | or brackets with it.
    private func registerShortcuts() {
        hotKeys.append(HotKey(keyCode: kVK_ANSI_G, modifiers: optionKey) { [weak self] in
            self?.overview.close()
            self?.picker.toggle()
        })
        hotKeys.append(HotKey(keyCode: kVK_Space, modifiers: controlKey | optionKey) { [weak self] in
            self?.picker.close()
            self?.overview.toggle()
        })
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (slot, key) in zip(SetLibrary.slots, digits) {
            hotKeys.append(HotKey(keyCode: key, modifiers: controlKey | optionKey) { [weak self] in
                self?.picker.close()
                self?.overview.close()
                self?.tiler.recall(slot: slot)
            })
        }
    }

    /// The gap event tap and focus observers need Accessibility access. Until it is granted,
    /// ask once and check every second.
    private func startWhenTrusted() {
        guard !gaps.start() else { return }
        AXWindow.promptForTrust()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXWindow.isTrusted, self.gaps.start() else { return }
                self.trustTimer?.invalidate()
                self.groups.refreshObservers()
                self.status?.refresh()
            }
        }
    }

    /// `isogrid://layout/2x4`, `tile`, `set/1`, `overview`, `picker` and `dismiss`, for Raycast,
    /// Shortcuts or a shell.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "isogrid" {
            guard let screen = Screen.underMouse else { continue }
            switch url.host() {
            case "layout":
                guard let layout = TileLayout(url.lastPathComponent) else { continue }
                tiler.apply(layout, on: screen)
                status?.refresh()
            case "tile":
                tiler.tile(on: screen)
            case "set":
                guard let slot = Int(url.lastPathComponent) else { continue }
                tiler.recall(slot: slot)
            case "dismiss":
                overview.close()
                picker.close()
            case "overview":
                overview.open()
            case "picker":
                picker.open()
            default:
                break
            }
        }
    }
}

#if DEBUG
// `swift run Isogrid --snapshot <dir>` renders the picker and overview to PNGs for design review.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    Snapshot.run(into: URL(filePath: CommandLine.arguments[flag + 1]))
    exit(0)
}
#endif

if E2EServer.isEnabled {
    Settings.suiteName = E2EServer.suiteName
    UserDefaults.standard.removePersistentDomain(forName: E2EServer.suiteName)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
