import AppKit
import ScreenCaptureKit

/// Still images of windows for the overview. They need the optional Screen Recording
/// permission; without it the overview shows app icons.
enum Thumbnails {
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccess() {
        CGRequestScreenCaptureAccess()
    }

    /// Captures the given windows, each scaled so its longer side is about `maxSide` points.
    @concurrent nonisolated static func capture(_ ids: Set<CGWindowID>, maxSide: CGFloat) async -> [CGWindowID: CGImage] {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return [:] }
        let windows = content.windows.filter { ids.contains($0.windowID) }
        return await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            for window in windows {
                let id = window.windowID
                let frame = window.frame
                // Created here and handed to exactly one child task.
                nonisolated(unsafe) let filter = SCContentFilter(desktopIndependentWindow: window)
                group.addTask {
                    let config = SCStreamConfiguration()
                    let scale = min(1, maxSide / max(frame.width, frame.height, 1)) * 2
                    config.width = max(Int(frame.width * scale), 1)
                    config.height = max(Int(frame.height * scale), 1)
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    return (id, try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
                }
            }
            var images: [CGWindowID: CGImage] = [:]
            for await (id, image) in group {
                images[id] = image
            }
            return images
        }
    }
}
