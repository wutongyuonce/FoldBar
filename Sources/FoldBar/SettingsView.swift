import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FoldBarCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.down").font(.system(size: 24, weight: .semibold))
                    .frame(width: 44, height: 44).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("FoldBar").font(.system(size: 22, weight: .semibold))
                    Text("让菜单栏，只留下常用的。").foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }.padding(24)
            Picker("设置页面", selection: $model.tab) {
                Text("图标").tag(0)
                Text("通用").tag(1)
                Text("关于").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let message = model.message {
                        Label(message, systemImage: "exclamationmark.triangle").font(.callout)
                            .foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if model.tab == 0 { icons }
                    if model.tab == 1 { general }
                    if model.tab == 2 { about }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, minHeight: 500)
    }

    private var icons: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("拖动图标调整顺序，或在两行之间移动。离线图标保留原来的位置。")
                .font(.callout).foregroundStyle(.secondary)
            if !model.accessibility || !model.screenCapture { permissions }
            group(.visible, title: "顶部显示", symbol: "menubar.rectangle")
            group(.hidden, title: "下拉隐藏", symbol: "chevron.down.square")
            let ambiguous = model.live.filter { $0.id.hasPrefix("ambiguous:") }
            if !ambiguous.isEmpty {
                Text("以下图标无法稳定区分，保留在系统菜单栏中：\(ambiguous.map(\.name).joined(separator: "、"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("所有桌面和显示器共用此布局").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("重新检测") { Task { await model.refresh() } }.disabled(model.busy)
            }
        }
    }

    private func group(_ group: ItemGroup, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(model.records.filter { $0.group == group }) { record in
                        tile(record)
                            .onDrag { NSItemProvider(object: record.id as NSString) }
                            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                                accept(providers, group: group, before: record.id)
                            }
                    }
                    Text(model.records.contains(where: { $0.group == group }) ? "拖到末尾" : "将图标拖到这里")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 90, height: 76)
                        .onDrop(of: [.plainText], isTargeted: nil) { accept($0, group: group, before: nil) }
                }.padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        }
    }

    private func tile(_ record: ItemIdentity) -> some View {
        let live = model.live.first { $0.id == record.id }
        return VStack(spacing: 7) {
            if let image = model.images[record.id] {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 30, height: 27)
            } else {
                Image(systemName: live == nil ? "app.dashed" : "app").font(.system(size: 23)).frame(height: 27)
            }
            Text(record.name).font(.caption).lineLimit(1).frame(width: 76)
            if live == nil { Text("未运行").font(.system(size: 9)).foregroundStyle(.secondary) }
            else if live?.reason != nil { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .frame(width: 82, height: 76).opacity(live == nil ? 0.45 : 1)
        .help(live?.reason ?? record.name)
        .accessibilityLabel(record.name + (live == nil ? "，未运行" : ""))
    }

    private func accept(_ providers: [NSItemProvider], group: ItemGroup, before: String?) -> Bool {
        guard !model.busy, let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            Task { @MainActor in model.move(id, group: group, before: before) }
        }
        return true
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            permission("辅助功能", detail: "发现、排列和操作菜单栏图标", allowed: model.accessibility, action: model.requestAccessibility)
            permission("屏幕录制", detail: "仅在内存中显示图标图像，不保存录像或截图", allowed: model.screenCapture, action: model.requestCapture)
        }
    }

    private func permission(_ title: String, detail: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle").foregroundStyle(allowed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if !allowed { Button("授权", action: action) }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 24) {
            Toggle("开机时启动 FoldBar", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
            Divider()
            Text("必要权限").font(.headline)
            permissions
            Text("布局文件").font(.headline)
            Text(model.configurationURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([model.configurationURL]) }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FoldBar 1.0").font(.title2.weight(.semibold))
            Text("一个箭头，收起不常用的菜单栏图标。")
            Link("GitHub 源码", destination: URL(string: "https://github.com/wutongyuonce/FoldBar")!)
            Link("前往下载页面", destination: URL(string: "https://github.com/wutongyuonce/FoldBar/releases")!)
            Text("手动下载新版本，不检查或推送更新。\n采用 GPL-3.0 许可证。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
