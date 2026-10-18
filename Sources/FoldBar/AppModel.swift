import AppKit
import SwiftUI
import ServiceManagement
import ScreenCaptureKit
import FoldBarCore

@MainActor final class AppModel: ObservableObject {
    @Published var tab = 0
    @Published var records: [ItemIdentity] = []
    @Published var live: [LiveItem] = []
    @Published var images: [String: NSImage] = [:]
    @Published var message: String?
    @Published var accessibility = false
    @Published var screenCapture = false
    @Published var loginEnabled = false
    @Published var busy = false
    let platform = MenuBarPlatform()
    let configurationURL: URL
    private(set) var store: LayoutStore?
    var applyLayout: (() async throws -> Void)?
    private var refreshing = false

    init() {
        configurationURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldBar/config.json")
        do {
            store = try LayoutStore(file: configurationURL)
            records = store?.items ?? []
        } catch {
            message = "配置无法读取，已停止自动布局以保护原文件。请在访达检查 \(configurationURL.path)：\(error.localizedDescription)"
        }
        updatePermissions()
    }

    func updatePermissions() {
        accessibility = AXIsProcessTrusted()
        screenCapture = CGPreflightScreenCaptureAccess()
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() async {
        guard !refreshing, !busy else { return }
        refreshing = true
        defer { refreshing = false }
        updatePermissions()
        guard accessibility else { live = []; return }
        let found = await Task.detached(priority: .utility) { MenuBarPlatform.scan() }.value
        live = found
        do {
            let eligible = found.filter { !$0.id.hasPrefix("ambiguous:") }
            try store?.discover(eligible.map { ItemIdentity(id: $0.id, name: $0.name) })
            records = store?.items ?? []
        } catch { message = "无法保存新图标，原配置已保留：\(error.localizedDescription)" }
        let valid = Set(found.map(\.id)).union(records.filter { $0.group == .hidden }.map(\.id))
        images = images.filter { valid.contains($0.key) }
        guard screenCapture else { return }
        for item in found {
            if busy || Task.isCancelled { break }
            let collisions = found.filter { $0.id != item.id && $0.frame.intersection(item.frame).width > min($0.frame.width, item.frame.width) * 0.8 }
            // Native overflow can give many items identical placeholder geometry.
            // Such geometry is not evidence of which pixels belong to this item.
            guard collisions.isEmpty else { continue }
            if let image = try? await platform.capture(item) { images[item.id] = image }
        }
    }

    func move(_ id: String, group: ItemGroup, before: String?) {
        guard !busy, let store else { return }
        if let item = live.first(where: { $0.id == id }), let reason = item.reason {
            message = reason
            return
        }
        Task {
            busy = true
            defer { busy = false }
            do {
                try store.move(id: id, to: group, before: before)
                records = store.items
                try await applyLayout?()
                message = nil
            } catch { message = error.localizedDescription }
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            updatePermissions()
            if SMAppService.mainApp.status == .requiresApproval {
                message = "请在系统设置 → 通用 → 登录项中允许 FoldBar"
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { message = "无法更改开机启动：\(error.localizedDescription)"; updatePermissions() }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestCapture() {
        Task {
            do { _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
            catch { message = "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 FoldBar，然后重新打开应用" }
            updatePermissions()
        }
    }
}
