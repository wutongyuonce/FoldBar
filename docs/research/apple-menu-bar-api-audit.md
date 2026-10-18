# Apple 菜单栏 API 核查

核查日期：2026-10-18。依据 Apple 官方文档和本机 macOS 27.0 SDK；未借用 Ice 实现来证明系统能力。本报告说明 API 合同，不代表已完成真实菜单栏、多桌面或多显示器验收。

## 发现、交互与控制的边界

`AXUIElementCreateApplication` 可取得进程的辅助功能根元素，`kAXExtrasMenuBarAttribute` 是公开的应用属性；可尝试读取菜单栏附加项及其子元素。元素是否存在、属性是否提供、身份是否稳定必须运行时判断，不能将一次枚举结果视为完整系统清单。[Apple 属性文档](https://developer.apple.com/documentation/applicationservices/kaxextrasmenubarattribute)

`AXUIElementCopyActionNames` 枚举元素实际支持的操作，再通过 `AXUIElementPerformAction` 请求操作。不能假定所有图标支持相同操作，也不能把 AX Press 等同于原应用右键菜单。`kAXErrorCannotComplete` 可能代表应用仍在处理模态菜单，而非确定失败；盲目重试可能重复触发。应设置有限的 AX 消息超时，并重新观察状态。[Apple AX 接口文档](https://developer.apple.com/documentation/applicationservices/axuielement_h)

本次检查 `NSStatusItem`、AX 元素接口和相关常量，**未找到授权第三方 app 统一隐藏或重排其他进程状态项的公开专用 API**。这是对已检查文档/头文件的结论，不是对所有系统内部能力的证明。`NSStatusItem.isVisible`、`length` 等属性控制本应用持有的状态项；不能由此推导能取得或修改其他 app 的 `NSStatusItem`。AX 属性写入也必须先检查 `AXUIElementIsAttributeSettable`，其存在并不保证菜单栏项位置可写。[Apple NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)

因此菜单栏布局控制属于独立平台适配能力：验证实际结果，保留恢复路径，明确记录未公开行为的兼容风险。公开事件投递接口可模拟输入，但不为特定系统拖动手势提供成功保证；“能发事件”与“已完成隐藏/排序”必须分别验证。

## macOS 27 的下拉栏生命周期

macOS 27 新增 `NSStatusItemExpandedInterfaceDelegate` 和 `NSStatusItemExpandedInterfaceSession`。自定义下拉窗口应随 `statusItem(_:didBegin:)` 显示、随 `statusItemDidEndExpandedInterfaceSession(_:animated:)` 隐藏；主动关闭时调用 session 的 `cancel()`。Apple 建议使用这套会话参与键盘导航与菜单跟踪。它管理 FoldBar 自己的展开界面，不提供跨 app 布局能力。设置了 `NSMenu` 的状态项不会收到这些展开回调。[Apple delegate](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate)、[Apple session](https://developer.apple.com/documentation/appkit/nsstatusitemexpandedinterfacesession)、[WWDC26 Modernize your AppKit app](https://developer.apple.com/videos/play/wwdc2026/289/)

部署目标低于 27 时需 availability 分支；在 27 的实际路径应采用新会话 API，避免直接沿用旧项目手动鼠标跟踪逻辑。

## 图像与文件残留

ScreenCaptureKit 的 `SCScreenshotManager.captureScreenshot` 和 `SCScreenshotConfiguration` 从 macOS 26 可用；`fileURL = nil` 明确表示不保存截图文件，图像从 `SCScreenshotOutput` 返回。适合仅在内存维护图标截图的约束。[Apple screenshot manager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)、[Apple fileURL](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/fileurl)

这些声明不保证被移出屏幕、不可见或不在可共享窗口列表中的状态项仍可截图，也不保证区域截图捕获的是特定图标。缓存缺失、权限撤销、屏幕切换后必须按当前能力处理，不能通过文档推定隐藏状态窗口捕获可用。应以实际捕获结果和窗口身份校验；截图仅用于呈现，不作为持久身份。

## 可复核的本机 SDK 证据

SDK 根：`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`，`SDKSettings.json` 的 `Version` 为 `27.0`。

相对该根目录：

- `System/Library/Frameworks/AppKit.framework/Headers/NSStatusItem.h:27–34,78–84`：27.0 delegate、会话回调与属性；`70–76`：本状态项可见性和 autosave。
- `System/Library/Frameworks/AppKit.framework/Headers/NSStatusItemExpandedInterfaceSession.h:13–19`：27.0 会话和取消。
- `System/Library/Frameworks/ScreenCaptureKit.framework/Headers/SCScreenshotManager.h:103–105,129–131,164–179`：nil URL 不写文件、26.0 截图接口及输出。
- `System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Headers/AXAttributeConstants.h:1004–1010`：应用属性与 AXExtrasMenuBar。
- 同目录 `AXUIElement.h:188–223,283–331,387–402`：属性可写性、支持操作、操作结果和超时语义。

SDK 检查与文档核查已完成；隐藏、重排、隐藏项截图、真实菜单、Spaces、全屏、自动隐藏菜单栏和显示器热插拔均仍须逐项实测。
