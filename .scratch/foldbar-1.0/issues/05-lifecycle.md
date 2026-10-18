# 05: 设置与安装生命周期

**What to build:** 设置与安装生命周期，独立实现并以当前 Apple API 和实测为准。

**Blocked by:** 01: 启动与发现图标

**Status:** ready-for-agent

- [ ] 开机启动使用系统注册。
- [x] About位于设置，版本1.0与GitHub链接。
- [ ] 制作DMG、记录卸载步骤、退出释放隐藏。

## Comments

2026-10-18：已实现SMAppService开关、About、手动下载、退出清理与DMG；About和旧包正常退出已观察，DMG镜像/签名/包内二进制通过检查。开机启动未实际重新登录验证。
