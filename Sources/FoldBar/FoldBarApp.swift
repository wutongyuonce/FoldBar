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
    private var awaitingManualRecovery = false
    private var recoveryInteraction: MenuInteraction?
    private var lastSignature = ""
    private var failedSignature = ""
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
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        applicationMenu.addItem(withTitle: "退出 FoldBar", action: #selector(quit), keyEquivalent: "q").target = self
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
        model.applyLayout = { [weak self] in
            if let recovery = self?.recoveryInteraction, try await recovery.observe() == .open {
                throw PlatformError.unavailable("原应用界面仍然打开，请先关闭它再重新检测")
            }
            self?.failedSignature = ""
            self?.awaitingManualRecovery = false
            self?.recoveryInteraction = nil
            try await self?.reconcile()
        }
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
        let localAnchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let anchor: CGRect
        if let quartz = ownFrame(arrow) {
            let height = NSScreen.screens.first?.frame.height ?? 0
            anchor = CGRect(x: quartz.minX, y: height - quartz.maxY, width: quartz.width, height: quartz.height)
        } else { anchor = localAnchor }
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
        boundary.length = 1
        // Drop stale screen images before discovering the new active display.
        model.images = [:]
        lastSignature = ""
        failedSignature = ""
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await refreshAndApply()
        }
    }

    private func refreshAndApply() async {
        guard !interacting, !reconciling else { pending = true; return }
        await model.refresh()
        guard !awaitingManualRecovery else { boundary.length = 1; return }
        guard model.accessibility, model.screenCapture, model.store != nil else { boundary.length = 1; lastSignature = ""; failedSignature = ""; return }
        let signature = model.live.map(\.id).joined(separator: "|") + model.records.map { $0.id + $0.group.rawValue }.joined(separator: "|")
        guard signature != lastSignature, signature != failedSignature else { return }
        do { try await reconcile(); lastSignature = signature }
        catch { failedSignature = signature; model.message = error.localizedDescription + "。解决后点击“重新检测”重试。" }
    }

    private func ownElement(_ item: NSStatusItem) -> AXUIElement? {
        // macOS 27 hosts status items in MenuBarAgent. The local button's window
        // transform may describe the backing surface, not its presented position.
        let root = AXUIElementCreateApplication(getpid())
        if let bar = MenuBarPlatform.attribute(root, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            let children = MenuBarPlatform.attribute(bar as! AXUIElement, "AXChildren") as? [AXUIElement] ?? []
            let label = item === arrow ? "FoldBar" : "FoldBar 布局边界"
            return children.first(where: { (MenuBarPlatform.attribute($0, "AXDescription") as? String) == label })
        }
        return nil
    }

    private func ownFrame(_ item: NSStatusItem) -> CGRect? {
        if let element = ownElement(item), let frame = MenuBarPlatform.rect(element) { return frame }
        guard let button = item.button, let window = button.window else { return nil }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func reconcile() async throws {
        guard !reconciling else { pending = true; return }
        guard !interacting, model.accessibility, model.screenCapture, model.store != nil else { boundary.length = 1; return }
        reconciling = true
        model.busy = true
        boundary.length = 1
        defer {
            reconciling = false
            model.busy = false
            if pending { pending = false; Task { await refreshAndApply() } }
        }
        do {
            // A length assignment does not synchronously present host-rendered items.
            // Allow a bounded interval for fresh AX hit tests before injecting input.
            for _ in 0..<6 {
                let movable = model.live.filter { $0.reason == nil }
                if movable.allSatisfy({ model.platform.isPresented($0.element) }) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let active = model.records.compactMap { record in model.live.first { $0.id == record.id && $0.reason == nil } }
            let hiddenIDs = Set(model.records.filter { $0.group == .hidden }.map(\.id))
            let currentVisibleOrder = active.sorted { (MenuBarPlatform.rect($0.element)?.minX ?? 0) < (MenuBarPlatform.rect($1.element)?.minX ?? 0) }.map(\.id)
            // Initial discovery already records observed order. Do not inject
            // desktop input just to normalize gaps or move our own arrow.
            if hiddenIDs.isEmpty, currentVisibleOrder == active.map(\.id) { return }
            let visibleBefore = active.filter { !hiddenIDs.contains($0.id) && model.platform.isPresented($0.element) }
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
            let expected = [ItemGroup.hidden, .visible].flatMap { group in
                model.records.filter { $0.group == group }.compactMap { record in
                    model.live.first { $0.id == record.id && $0.reason == nil }
                }
            }
            let actual = expected.sorted { (MenuBarPlatform.rect($0.element)?.minX ?? 0) < (MenuBarPlatform.rect($1.element)?.minX ?? 0) }
            guard actual.map(\.id) == expected.map(\.id) else {
                throw PlatformError.unavailable("系统图标顺序与配置不一致，已停止隐藏；此布局尚未成功应用")
            }
            if model.records.contains(where: { record in record.group == .hidden && model.live.contains(where: { $0.id == record.id }) }) {
                // NSStatusItem.length only allocates our own space. Whether the OS
                // overflows items on its left is observed rather than API-guaranteed.
                boundary.length = max(10_000, (NSScreen.screens.map { $0.frame.width }.max() ?? 0) * 2)
                try await Task.sleep(for: .milliseconds(200))
                guard let arrowElement = ownElement(arrow), model.platform.isPresented(arrowElement), let arrowFrame = ownFrame(arrow),
                      NSScreen.screens.contains(where: { MenuBarPlatform.quartzFrame($0).contains(arrowFrame) }),
                      visibleBefore.allSatisfy({ model.platform.isPresented($0.element) }),
                      active.filter({ hiddenIDs.contains($0.id) }).allSatisfy({ !model.platform.isPresented($0.element) }) else {
                    throw PlatformError.unavailable("macOS 没有可靠完成指定图标的隐藏，已释放隐藏边界；配置已保留，但此布局尚未应用")
                }
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
        model.busy = true
        layoutTask = Task {
            let interaction = MenuInteraction(platform: self.model.platform, item: item, right: right,
                exposure: {
                    self.boundary.length = 1
                    try await Task.sleep(for: .milliseconds(180))
                }, restoration: { canMove in
                    self.interacting = false
                    if canMove { try await self.reconcile() }
                    else { self.boundary.length = 1; self.awaitingManualRecovery = true }
                })
            do {
                try await runNativeInteraction(interaction)
            } catch {
                self.recoveryInteraction = interaction
                self.boundary.length = 1
                self.model.message = error.localizedDescription
            }
            self.interacting = false
            self.model.busy = false
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
    func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        if NSApp.currentEvent?.type == .rightMouseUp { statusClick() } else { showDrawer() }
    }
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
    func makeNSView(context: Context) -> NativeIconButton {
        let button = NativeIconButton()
        button.target = button
        button.action = #selector(NativeIconButton.activate)
        return button
    }
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
    @objc func activate() { callback?(false) }
    override func mouseUp(with event: NSEvent) { callback?(false) }
    override func rightMouseUp(with event: NSEvent) { callback?(true) }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}
