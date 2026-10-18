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

## 补充：macOS 27 的系统原生溢出行为

Apple 于 2026-09-28 发布的 [What's new for enterprise in macOS Golden Gate 27](https://support.apple.com/en-us/148830) 明确说明：菜单栏容不下全部项目时，系统自动隐藏一部分，并用紧凑的溢出指示器代替；按下该指示器可显示隐藏项目。因此 macOS 27 的项目消失可能是系统管理的溢出，不等于传统“用超长状态项把项目推到屏幕外”。

本次补充检查 `NSStatusBar.h`、`NSStatusItem.h`、`NSStatusItemExpandedInterfaceSession.h` 及 AX 常量，仍未发现公开的跨 app 溢出项目选择、显隐分组、排序或系统溢出会话 API。27 的 expanded interface 仍是本 app 自己状态项的展开窗口合同。系统设置的“Allow in the Menu Bar”可控制部分 app 项目，但 Apple 用户手册没有将其声明为第三方控制接口。[Apple macOS 27 菜单栏设置](https://support.apple.com/en-euro/guide/mac-help/mchlad96d366/27/mac/27)

观察到 MenuBarAgent AX 对话框和“隐藏菜单栏项目”按钮时，**可检验的推断**是：它是原生溢出展示模式的收起按钮；不能仅凭标签确定，更不能当作任意图标隐藏命令。相同占位坐标应视为当前不可定位，而非多个图标的真实可点击位置。

下一步最小实验（尚未执行）：在不改变任何排序、不做拖动、不给边界项设超长长度的条件下，记录该按钮的 AX 身份、支持动作、对话框子项及目标图标 frame/hit-test；对其实际支持的 Press 动作只执行一次，再读取状态。若对话框消失、按钮变成“显示…”/展开指示器，且原本可见子项变成同坐标占位，支持“收起系统溢出”假设；若无此变化则否定或继续调查。随后通过刚观察到的真实展开按钮恢复一次，比较图标是否获得独立可 hit-test frame。不得对旧占位坐标发送点击或 Command-drag。

在原生展开与收起能可逆确认之后，再单独测试一个临时自有状态项从正常宽度增大到屏幕宽度以上、再恢复，比较溢出项目集合及指示器。该实验可直接证伪“超长边界仍按传统方式工作”，且不需先改用户图标顺序。每次只改变一个因素，成功标准是 AX 状态和实际命中结果，而不是事件函数返回成功。
