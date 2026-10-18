# FoldBar

一个向下箭头，收起不常用的 macOS 菜单栏图标。

**当前为开发候选，尚未通过完整 1.0 功能验收。** 已实现原生界面、图标发现、布局模型、拖拽入口、权限与启动设置、内存截图和 DMG 构建。macOS 27 上的跨应用隐藏、原菜单交互、全屏及多显示器同步仍需要实机验收，不能以构建通过代替这些结果。

## 功能范围

- 左键箭头展开隐藏组；外部点击或 Esc 收起。
- 右键菜单只有“设置”和“退出”。
- 设置中的两组图标支持拖动排序和切换显隐，显示当前平台操作错误。
- 按应用槽位保存单图标应用的顺序、显隐和离线位置；新图标默认显示并追加。
- 开机启动由 macOS ServiceManagement 注册，默认关闭。
- About 位于设置中，显示 1.0、GitHub 源码与下载链接。
- 手动下载更新，没有更新检查、推送、遥测或后台下载服务。

### 当前限制

单图标应用以 bundle ID 对应的“应用槽位”记忆位置，图标内容变化或应用重启仍继承显隐与顺序。应用提供独立 `AXIdentifier` 时可区分其多个同时存在的图标（合并检查同一应用的多个运行实例）；同一应用同时存在多个无法区分的图标时，设置页提示限制，不猜测其身份。

macOS 27 的原生溢出区可能不给隐藏图标提供独立可命中的位置。FoldBar 不能把重叠坐标的截图冒充成某个真实图标，也不会在该坐标盲目注入拖动。操作失败会停止隐藏并保留配置，待解决后点击“重新检测”。

跨进程重排/隐藏没有在本次核查中找到公开的专用 API。当前候选使用经结果检查的 Command 拖动与自身状态项的空间分配；这不是 Apple 对跨应用图标控制的保证。详见[当前设计与验证状态](docs/design.md)、[验证记录](docs/verification.md)和[Apple API 调查](docs/research/apple-menu-bar-api-audit.md)。

## 构建与检查

需要 Apple Silicon Mac、包含 macOS 27 SDK 的 Swift 工具链。本机使用 Swift 6.4 + Command Line Tools；无需第三方依赖或完整 Xcode。部署目标为 macOS 14，但当前只在 macOS 27.0.1 运行检查过部分功能。

```sh
swift run CoreChecks
python3 scripts/build.py
```

输出：`dist/FoldBar.app` 与 `dist/FoldBar-1.0-arm64.dmg`。脚本组装应用、执行 ad-hoc 签名、检查签名并验证磁盘镜像。该包**未公证**，首次打开可能需要在系统设置中确认允许；项目没有 Developer ID 发行证书。

只构建开发应用包：

```sh
python3 scripts/build.py --debug --no-dmg
```

将 DMG 中的 FoldBar 拖入 Applications 后运行，在应用设置中按需授权。请不要同时运行多个菜单栏管理器进行验收。重新构建的 ad-hoc 签名包可能需要系统重新核查权限。

## 数据与卸载

FoldBar 主动维护一个数据文件：

```text
~/Library/Application Support/FoldBar/config.json
```

其中只含布局版本、可持久登记的图标身份、显示名称、显隐及顺序。截图仅在内存中处理，不写录像、截图缓存、日志文件或更新数据库。原子保存期间可能有短暂的写入暂存文件。

卸载步骤：

1. 在 FoldBar 设置中关闭“开机时启动”，然后退出应用，释放隐藏边界。
2. 将 Applications 中的 `FoldBar.app` 移到废纸篓。
3. 如不保留布局，删除 `~/Library/Application Support/FoldBar/`。
4. 在系统设置的隐私权限页移除 FoldBar。macOS 27 的相关入口可能显示为“设备控制和数据访问”“录屏与系统录音”；旧版本名称可能是“辅助功能”“屏幕录制”。权限数据库由 macOS 管理，不要手动修改。

AppKit/macOS 还可能维护以下系统文件；存在时可在退出后按需清理：

- `~/Library/Preferences/io.github.wutongyuonce.FoldBar.plist`
- `~/Library/Saved Application State/io.github.wutongyuonce.FoldBar.savedState/`
- `~/Library/Logs/DiagnosticReports/` 中以 FoldBar 开头的诊断报告。

FoldBar 没有自建 LaunchAgent、登录辅助程序、守护进程或沙盒容器。源码目录中的 `.build/` 和 `dist/` 属于开发产物，不会随拖入 Applications 的应用安装到用户数据目录。系统登录注册和诊断记录不属于“只主动保存一个 JSON”的保证范围。

## 开发工作流

规格与六张开发票位于[本地 Markdown tracker](.scratch/foldbar-1.0/)，随源码版本管理。已确认的目标见[1.0 规格](.scratch/foldbar-1.0/spec.md)，词汇见[GLOSSARY](GLOSSARY.md)，取舍见[ADRs](docs/adr/)。开发票的状态和检查记录如实区分实现与实机验收。

## License

GPL-3.0。FoldBar 独立实现；[Ice](https://github.com/jordanbaird/Ice) 仅作为功能和 UI 参考，没有复制其应用代码。API 选型依据当前 Apple 文档、macOS SDK 和实际系统观察。
