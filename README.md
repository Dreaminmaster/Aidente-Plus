# Aidente-Plus

独立的 MacBook 电池与充电管理项目。应用名称仍为 **Aidente**，当前版本 **6.1 / Build 21**。

基于开源 Aidente / Stasis 工作继续开发，保留 GPL-3.0 及第三方许可证。与 AppHouseKitchen、AlDente 无隶属关系；没有包含 AlDente 闭源程序、付费激活逻辑或原版素材。不宣称与 AlDente Pro 的全部功能、视觉或动画完全一致。

## 安装

从本仓库 [Releases](https://github.com/Dreaminmaster/Aidente-Plus/releases) 下载 DMG，将 Aidente 拖入“应用程序”。目前提供 Apple Silicon 构建，最低系统版本 macOS 14；主要在 Apple Silicon / macOS 27 上进行本机验证。

首次启用“管理充电”或更新控制客户端时，macOS 会请求管理员授权。密码只在系统窗口输入。监测不需要管理员权限；普通限充不需要辅助功能、屏幕录制或完全磁盘访问权限。可选的合盖锁屏按系统要求单独授权。

此安装包没有 Apple 公证；开发签名不是 Developer ID 分发签名。不要关闭 SIP 或全局 Gatekeeper。

仓库是私有的，下载与更新须使用有权限的 GitHub 账号。应用不保存 GitHub 令牌，更新入口打开浏览器中的私有发行页。

## 本版交互

- 外观：设置 → 外观 → 其他 → 界面外观，选择跟随系统、浅色或深色；菜单底部“更多”也有入口。
- 指示灯：未启用管理充电时，点击提示中的“前往充电控制”直接跳转，不会替你打开充电管理。
- 菜单栏：插拔及充电状态变化通过系统电源通知刷新；普通功率读数保留自选刷新间隔。
- 上限滑条：拖动显示目标数值，松开才提交；蓝色表示当前电量，白色滑块表示上限，竖向虚线表示航海下界。充电高光、分流光带支持减少动态效果。
- App 用量：默认显示所有普通运行应用，包括空闲应用；可切仅高能耗，并可选择后台进程。按名称固定排序，鼠标停留/退出确认时固定名单位置；用量数字仍可更新。超过窗口高度可滚动查看。
- 电量/功耗曲线：可按实际时间或跳过记录空档，悬停读取真实采样时间；可开关刻度。功率平均支持当前或过去 5/15/30 分钟。
- 小组件：底部编辑入口或长按底边进入编辑模式；编辑模式支持增删和排序，日常查看不拖动排序。

充电、航海、温控、MagSafe、睡眠行为、计划与原生快捷指令等代码也包含在仓库中。支持情况依机型/系统而异，实测与未测项目见[验收与限制](Docs/RELEASE-VALIDATION.md)。

## 构建与验证

要求 Xcode 或 Command Line Tools、Swift 6，以及 Apple Silicon Mac。依赖源码已放在 Vendor 中。

```sh
zsh BuildSupport/build_app.sh
# 只读预览；不会开启硬件充电管理
open -n Dist/Aidente.app --args --ui-preview --preview-window

zsh BuildSupport/test_status_events.sh
zsh BuildSupport/test_completion.sh
zsh BuildSupport/test_charging.sh
zsh BuildSupport/test_parity.sh
zsh BuildSupport/test_native_policy.sh
zsh BuildSupport/test_uninstall.sh
```

规范构建入口是上述脚本，它同时打包 App、XPC 读取器和控制服务；Xcode 工程不是本版发行构建的验收入口。默认 ad-hoc 完整性签名；可通过 `AIDENTE_SIGNING_IDENTITY` 指定本机已有身份，不需要把证书私钥放入仓库。

```sh
zsh script/package_dmg.sh /absolute/path/to/Aidente-Plus.dmg
```

安装包脚本不会覆盖已有目标文件，并会挂载校验包内签名。

## 卸载

在 Aidente 内打开关于 → 完全卸载 Aidente，核对范围后执行。应用会先尝试恢复充电默认值，再移除控制服务和本账户数据，把 App/历史等移入废纸篓；失败会保留必要组件供重试。下载的 DMG、源码、另存的诊断文件不属于自动清理范围。详见[卸载说明](Docs/UNINSTALL.md)。

## 来源与许可证

- 上游 Aidente：<https://github.com/buffoons8-sketch/Aidente>
- Stasis：<https://github.com/srimanachanta/Stasis>
- [GPL-3.0](LICENSE) 与 [第三方声明](THIRD_PARTY_NOTICES.md)
