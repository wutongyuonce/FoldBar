import AppKit
import SwiftUI
import FoldBarCore

@main struct FoldBarApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var arrow: NSStatusItem!
    private var boundary: NSStatusItem!
    private var settings: NSWindow?
    private var drawer: NSPanel?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var observations: [NSObjectProtocol] = []
    private var reconciling = false
    private var pending = false
    private var interacting = false
    private var lastSignature = ""
    private var layoutTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        arrow = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        arrow.button?.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "FoldBar")
        arrow.button?.toolTip = "FoldBar"
        arrow.button?.target = self
        arrow.button?.action = #selector(statusClick)
        if #available(macOS 27.0, *) {
            arrow.expandedInterfaceDelegate = self
            arrow.button?.sendAction(on: [.rightMouseUp])
        } else { arrow.button?.sendAction(on: [.leftMouseUp, .rightMouseUp]) }
        boundary = NSStatusBar.system.statusItem(withLength: 1)
        boundary.button?.setAccessibilityLabel("FoldBar 布局边界")
        model.applyLayout = { [weak self] in try await self?.reconcile() }
        let outside: (NSEvent) -> Void = { [weak self] event in
            Task { @MainActor in
                guard let self, let drawer = self.drawer, drawer.isVisible else { return }
                if event.window !== drawer { self.dismissDrawer() }
            }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: outside) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            if event.type == .keyDown, event.keyCode == 53 {
                self?.dismissDrawer()
                return nil
            }
            outside(event)
            return event
        }) { monitors.append(monitor) }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            observations.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.environmentChanged() }
            })
        }
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.environmentChanged() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAndApply() }
        }
        Task { await refreshAndApply() }
        if model.records.isEmpty || !model.accessibility || model.message != nil { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            dismissDrawer()
            let menu = NSMenu()
            menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
            menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q").target = self
            if let button = arrow.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 2), in: button) }
        } else if drawer?.isVisible == true { dismissDrawer() } else { showDrawer() }
    }

    @objc func showSettings() {
        dismissDrawer()
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "FoldBar 设置"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
        Task { await model.refresh() }
    }

    private func showDrawer() {
        guard let button = arrow.button, let window = button.window else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 70), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        let hidden = model.records.filter { record in record.group == .hidden && model.live.contains(where: { $0.id == record.id }) }
        let width = min(CGFloat(max(1, hidden.count)) * 48 + 24, (window.screen?.visibleFrame.width ?? 600) - 32)
        panel.setContentSize(NSSize(width: max(200, width), height: 72))
        panel.contentView = NSHostingView(rootView: DrawerView(model: model) { [weak self] id, right in self?.activate(id, right: right) })
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? window.screen ?? NSScreen.main
        let bounds = screen?.frame ?? anchor.insetBy(dx: -300, dy: -300)
        panel.setFrameOrigin(NSPoint(x: min(max(anchor.midX - panel.frame.width / 2, bounds.minX + 8), bounds.maxX - panel.frame.width - 8), y: bounds.maxY - NSStatusBar.system.thickness - panel.frame.height - 8))
        drawer = panel
        panel.orderFrontRegardless()
    }

    private func dismissDrawer() {
        if #available(macOS 27.0, *), let session = arrow?.expandedInterfaceSession { session.cancel() }
        drawer?.orderOut(nil)
        drawer = nil
    }

    private func environmentChanged() {
        dismissDrawer()
        // Drop stale screen images before discovering the new active display.
        model.images = [:]
        lastSignature = ""
        Task { await refreshAndApply() }
    }

    private func refreshAndApply() async {
        guard !interacting, !reconciling else { pending = true; return }
        await model.refresh()
        guard model.accessibility, model.screenCapture, model.store != nil else { boundary.length = 1; return }
        let signature = model.live.map(\.id).joined(separator: "|") + model.records.map { $0.id + $0.group.rawValue }.joined(separator: "|")
        guard signature != lastSignature else { return }
        lastSignature = signature
        do { try await reconcile() }
        catch { model.message = error.localizedDescription }
    }

    private func ownFrame(_ item: NSStatusItem) -> CGRect? {
        // macOS 27 hosts status items in MenuBarAgent. The local button's window
        // transform may describe the backing surface, not its presented position.
        let root = AXUIElementCreateApplication(getpid())
        if let bar = MenuBarPlatform.attribute(root, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            let children = MenuBarPlatform.attribute(bar as! AXUIElement, "AXChildren") as? [AXUIElement] ?? []
            let label = item === arrow ? "FoldBar" : "FoldBar 布局边界"
            if let element = children.first(where: { (MenuBarPlatform.attribute($0, "AXDescription") as? String) == label }),
               let rect = MenuBarPlatform.rect(element) { return rect }
        }
        guard let button = item.button, let window = button.window else { return nil }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func reconcile() async throws {
        guard !reconciling else { pending = true; return }
        guard !interacting, model.accessibility, model.screenCapture, model.store != nil else { boundary.length = 1; return }
        reconciling = true
        boundary.length = 1
        defer {
            reconciling = false
            if pending { pending = false; Task { await refreshAndApply() } }
        }
        do {
            for group in [ItemGroup.visible, .hidden] {
                var anchor = ownFrame(group == .visible ? arrow : boundary)
                for record in model.records.filter({ $0.group == group }).reversed() {
                    guard let item = model.live.first(where: { $0.id == record.id }), item.reason == nil,
                          let target = anchor, let current = MenuBarPlatform.rect(item.element) else { continue }
                    if group == .hidden, model.images[item.id] == nil {
                        throw PlatformError.unavailable("尚未捕获“\(item.name)”的图标。请先在系统菜单栏中展开它，再重新检测；为保持可访问，已停止隐藏。")
                    }
                    let desired = CGPoint(x: target.minX - current.width / 2 - 2, y: target.midY)
                    if abs(current.maxX - target.minX) > 10 { try await model.platform.move(item, to: desired) }
                    anchor = MenuBarPlatform.rect(item.element)
                }
            }
            if model.records.contains(where: { record in record.group == .hidden && model.live.contains(where: { $0.id == record.id }) }) {
                // NSStatusItem.length only allocates our own space. Whether the OS
                // overflows items on its left is observed rather than API-guaranteed.
                boundary.length = max(10_000, (NSScreen.screens.map { $0.frame.width }.max() ?? 0) * 2)
            }
        } catch {
            boundary.length = 1
            throw error
        }
    }

    private func activate(_ id: String, right: Bool) {
        guard !interacting, !reconciling, let item = model.live.first(where: { $0.id == id }) else { return }
        dismissDrawer()
        interacting = true
        layoutTask = Task {
            do {
                try await restoringLayout(operation: {
                    self.boundary.length = 1
                    try await Task.sleep(for: .milliseconds(180))
                    try self.model.platform.press(item, right: right)
                    // Wait for the original menu or panel to finish before restoring.
                    for _ in 0..<600 {
                        try await Task.sleep(for: .milliseconds(200))
                        let root = AXUIElementCreateApplication({ var pid: pid_t = 0; AXUIElementGetPid(item.element, &pid); return pid }())
                        let menu = MenuBarPlatform.attribute(root, "AXFocusedUIElement")
                        if menu == nil && NSEvent.pressedMouseButtons == 0 { break }
                    }
                }, restore: {
                    self.interacting = false
                    try await self.reconcile()
                })
            } catch { self.boundary.length = 1; self.model.message = error.localizedDescription }
            self.interacting = false
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        layoutTask?.cancel()
        timer?.invalidate()
        boundary.length = 1
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        for observer in observations {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        NSStatusBar.system.removeStatusItem(boundary)
        NSStatusBar.system.removeStatusItem(arrow)
    }
}

@available(macOS 27.0, *)
extension AppDelegate: @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) { showDrawer() }
    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        drawer?.orderOut(nil)
        drawer = nil
    }
}

private struct DrawerView: View {
    @ObservedObject var model: AppModel
    let activate: (String, Bool) -> Void
    var body: some View {
        let items = model.records.filter { record in record.group == .hidden && model.live.contains { $0.id == record.id } }
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if items.isEmpty { Text("还没有隐藏图标").foregroundStyle(.secondary).frame(width: 176, height: 48) }
                ForEach(items) { item in
                    IconButton(image: model.images[item.id], title: item.name) { right in activate(item.id, right) }
                        .frame(width: 40, height: 44)
                }
            }.padding(12)
        }
    }
}

private struct IconButton: NSViewRepresentable {
    let image: NSImage?
    let title: String
    let action: (Bool) -> Void
    func makeNSView(context: Context) -> NativeIconButton { NativeIconButton() }
    func updateNSView(_ button: NativeIconButton, context: Context) {
        button.image = image ?? NSImage(systemSymbolName: "app", accessibilityDescription: title)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .rounded
        button.isBordered = false
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.callback = action
    }
}

private final class NativeIconButton: NSButton {
    var callback: ((Bool) -> Void)?
    override func mouseUp(with event: NSEvent) { callback?(false) }
    override func rightMouseUp(with event: NSEvent) { callback?(true) }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}
