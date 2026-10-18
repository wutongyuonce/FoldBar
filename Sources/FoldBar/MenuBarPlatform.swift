import AppKit
import ApplicationServices
import ScreenCaptureKit
import FoldBarCore

struct LiveItem: Identifiable {
    let id: String
    let name: String
    let bundleID: String
    let element: AXUIElement
    let frame: CGRect
    let reason: String?
}

enum PlatformError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

/// The only module interpreting cross-process accessibility and desktop geometry.
@MainActor final class MenuBarPlatform {
    nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    nonisolated static func rect(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, "AXPosition"), let size = attribute(element, "AXSize"),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    nonisolated static func scan() -> [LiveItem] {
        guard AXIsProcessTrusted() else { return [] }
        var result: [LiveItem] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != getpid() {
            guard let bundle = app.bundleIdentifier else { continue }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.12)
            guard let bar = Self.attribute(root, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            let children = Self.attribute(bar as! AXUIElement, "AXChildren") as? [AXUIElement] ?? []
            let candidates = children.flatMap { child -> [AXUIElement] in
                if (Self.attribute(child, "AXRole") as? String) == "AXMenuBarItem" { return [child] }
                if (Self.attribute(child, "AXRole") as? String) == "AXGroup" {
                    return (Self.attribute(child, "AXChildren") as? [AXUIElement] ?? [])
                        .filter { (Self.attribute($0, "AXRole") as? String) == "AXMenuBarItem" }
                }
                return []
            }
            let identifiers = candidates.map { Self.attribute($0, "AXIdentifier") as? String ?? "" }
            for (index, element) in candidates.enumerated() {
                guard let frame = Self.rect(element), frame.width > 0, frame.height > 0 else { continue }
                let identifier = identifiers[index]
                let uniqueIdentifier = !identifier.isEmpty && identifiers.filter { $0 == identifier }.count == 1
                // A single unnamed item has a stable application slot. Multi-item apps
                // require an actual distinct identifier; dynamic labels are not identity.
                let ambiguous = candidates.count > 1 && !uniqueIdentifier
                let key = uniqueIdentifier ? "\(bundle)/ax:\(identifier)" : "\(bundle)/single"
                let system = bundle.hasPrefix("com.apple.")
                result.append(LiveItem(
                    id: ambiguous ? "ambiguous:\(bundle):\(index)" : key,
                    name: bundle == "com.apple.MenuBarAgent" ? (Self.attribute(element, "AXDescription") as? String ?? app.localizedName ?? bundle) : (app.localizedName ?? bundle),
                    bundleID: bundle,
                    element: element,
                    frame: frame,
                    reason: ambiguous ? "此应用有多个无法稳定区分的图标" : (system ? "系统图标由 macOS 管理" : nil)
                ))
            }
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    func capture(_ item: LiveItem) async throws -> NSImage {
        guard CGPreflightScreenCaptureAccess() else { throw PlatformError.unavailable("需要屏幕录制权限以显示真实图标") }
        let rect = Self.rect(item.element) ?? item.frame
        guard NSScreen.screens.contains(where: { Self.quartzFrame($0).contains(rect) }) else {
            throw PlatformError.unavailable("图标当前不在可捕获区域，尚未取得图标图像")
        }
        // Current public screenshot API: capture exactly the icon region, no disk output.
        let image: CGImage
        if #available(macOS 26.0, *) {
            let configuration = SCScreenshotConfiguration()
            configuration.fileURL = nil
            configuration.showsCursor = false
            configuration.dynamicRange = .sdr
            let output = try await SCScreenshotManager.captureScreenshot(rect: rect, configuration: configuration)
            guard let value = output.sdrImage else { throw PlatformError.unavailable("系统没有返回图标图像") }
            image = value
        } else if #available(macOS 15.2, *) {
            image = try await SCScreenshotManager.captureImage(in: rect)
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.frame.contains(rect) }) else {
                throw PlatformError.unavailable("找不到图标所在屏幕")
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            configuration.width = Int(rect.width * 2)
            configuration.height = Int(rect.height * 2)
            configuration.showsCursor = false
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        return NSImage(cgImage: image, size: rect.size)
    }

    static func quartzFrame(_ screen: NSScreen) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    }

    func press(_ item: LiveItem, right: Bool) throws {
        var actions: CFArray?
        AXUIElementCopyActionNames(item.element, &actions)
        let supported = actions as? [String] ?? []
        let action = right ? "AXShowMenu" : "AXPress"
        guard supported.contains(action) else {
            throw PlatformError.unavailable(right ? "此图标未提供右键菜单操作" : "此图标未提供点击操作")
        }
        let result = AXUIElementPerformAction(item.element, action as CFString)
        // CannotComplete can be a menu tracking its modal event loop. Never retry it.
        guard result == .success || result == .cannotComplete else {
            throw PlatformError.unavailable("原应用没有接受操作（\(result.rawValue)）")
        }
    }

    /// Command-drag is a system gesture, not a documented cross-app layout API.
    /// Completion is determined by fresh AX geometry, never by event posting alone.
    func move(_ item: LiveItem, to point: CGPoint) async throws {
        guard AXIsProcessTrusted(), item.reason == nil else {
            throw PlatformError.unavailable(item.reason ?? "需要辅助功能权限")
        }
        guard NSEvent.pressedMouseButtons == 0, NSEvent.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else {
            throw PlatformError.unavailable("请松开鼠标和修饰键后再试")
        }
        guard let initial = Self.rect(item.element), let source = CGEventSource(stateID: .hidSystemState) else {
            throw PlatformError.unavailable("图标已退出或无法创建拖动事件")
        }
        let oldPointer = CGEvent(source: nil)?.location
        var mouseHeld = false
        defer {
            // Cancellation or a failing event constructor must never strand a drag.
            if mouseHeld, let release = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
                release.flags = []
                release.post(tap: .cghidEventTap)
            }
            if let oldPointer { CGWarpMouseCursorPosition(oldPointer) }
        }
        let start = CGPoint(x: initial.midX, y: initial.midY)
        for (type, location) in [(CGEventType.leftMouseDown, start), (.leftMouseDragged, point), (.leftMouseUp, point)] {
            try Task.checkCancellation()
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left) else {
                throw PlatformError.unavailable("无法创建拖动事件")
            }
            event.flags = type == .leftMouseUp ? [] : .maskCommand
            event.post(tap: .cghidEventTap)
            mouseHeld = type != .leftMouseUp
            try await Task.sleep(for: .milliseconds(80))
        }
        try await Task.sleep(for: .milliseconds(150))
        guard let current = Self.rect(item.element), abs(current.midX - point.x) <= max(70, current.width) else {
            throw PlatformError.unavailable("macOS 没有将“\(item.name)”移动到目标位置；已停止隐藏，请保持系统菜单栏可见")
        }
    }
}
