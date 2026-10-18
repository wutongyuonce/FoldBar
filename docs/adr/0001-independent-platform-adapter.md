# 依据当前 Apple API 独立实现平台适配

FoldBar 独立实现，Ice 代码与 UI 只作为参考。平台方案以 Apple 当前文档、macOS 27 SDK 和实测证据为准。优先采用公开的 Accessibility、ScreenCaptureKit、AppKit 和 ServiceManagement 接口；无法使用公开接口完成的图标控制须隔离、检查结果并清楚记录局限。

macOS 27 的状态项展开会话应优先评估，截图优先 ScreenCaptureKit。旧代码能够编译不代表其 API 仍受支持。用户没有要求更换已选的 GPL-3.0 许可证，因此继续保留该许可证；它不意味着项目派生自 Ice。

右键箭头仅提供设置和退出，About 位于设置页。保持最小产品范围，不导入其他菜单栏工具的附加功能。
