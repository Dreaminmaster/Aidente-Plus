# Aidente-Plus

独立的 MacBook 电池与充电管理项目。应用名称仍为 **Aidente**，当前版本 **6.2.2 / Build 24**。

基于开源 Aidente / Stasis 工作继续开发，保留 GPL-3.0 及第三方许可证。与 AppHouseKitchen、AlDente 无隶属关系；没有包含 AlDente 闭源程序、付费激活逻辑或原版素材。不宣称与 AlDente Pro 的全部功能、视觉或动画完全一致。

## 安装

从本仓库 [Releases](https://github.com/Dreaminmaster/Aidente-Plus/releases) 下载 DMG，将 Aidente 拖入“应用程序”。目前提供 Apple Silicon 构建，最低系统版本 macOS 14；主要在 Apple Silicon / macOS 27 上进行本机验证。

首次启用“管理充电”或更新控制客户端时，macOS 会请求管理员授权。密码只在系统窗口输入。监测不需要管理员权限；普通限充不需要辅助功能、屏幕录制或完全磁盘访问权限。可选的合盖锁屏按系统要求单独授权。

此安装包没有 Apple 公证；开发签名不是 Developer ID 分发签名。不要关闭 SIP 或全局 Gatekeeper。

仓库与发行包现已公开，不需要 GitHub 登录。6.2 启用公开发行页检查，自动检查仍由现有开关决定；更新包须通过 SHA-256、版本、arm64 和同一 Apple 开发者身份校验。

## 本版交互

- 外观：设置 → 外观 → 其他 → 界面外观，选择跟随系统、浅色或深色；菜单底部“更多”也有入口。
- 首次启动：提供“启用电池管理”和“稍后，仅查看”；查看无需授权，启用才安装共用后台服务。
- 指示灯：可先浏览模式，未启用时显示“尚未启用”和“启用并继续”。授权成功再应用选择；取消保持关闭。普通模式切换不重复安装服务。
- 新用户睡眠默认：保持当前充电策略；旧用户包括旧隐式默认保持原值。
- 菜单栏：插拔及充电状态变化通过系统电源通知刷新；普通功率读数保留自选刷新间隔。
- 上限滑条：拖动显示目标数值，松开才提交；蓝色表示当前电量，白色滑块表示上限，竖向虚线表示航海下界。充电高光、分流光带支持减少动态效果。
- App 用量：默认显示所有普通运行应用，包括空闲应用；可切仅高能耗，并可选择后台进程。按名称固定排序，鼠标停留/退出确认时固定名单位置；用量数字仍可更新。悬停时读数向左让位、展开退出按钮，平时右对齐；右键菜单也可退出。超过窗口高度可滚动查看。
- 功率分流：共同干流连续分叉，支持充电、保持、电池及混合供电。macOS26+可点击电脑展开/收起硬件分项；低于1W的细流隐藏但保留详情。仪表板提供功率总览和整图折叠。
- 通知：正向总开关控制全部提醒，子开关单独控制充电状态提醒；系统通知权限独立。
- 电量/功耗曲线：可按实际时间或跳过记录空档，悬停读取真实采样时间；可开关刻度。功率平均支持当前或过去 5/15/30 分钟。
- 菜单项目配置：主电池与读数共用排序；在设置内自由拖动原卡片，不生成另一份拖动预览。主图标样式和选项可折叠，读数目录保留。
- 材质：macOS 26+ 的液态玻璃使用 NSGlassEffectView 与 glassEffect；旧系统回退毛玻璃。材质和日夜外观分别选择，跟随窗口与菜单面板。
- 小组件：底部编辑入口或长按底边进入编辑模式；编辑模式支持增删和排序，日常查看不拖动排序。

充电、航海、温控、MagSafe、睡眠行为、计划与原生快捷指令等代码也包含在仓库中。支持情况依机型/系统而异，实测与未测项目见[验收与限制](Docs/RELEASE-VALIDATION.md)。

## 构建与验证

要求带 macOS 26 或更新 SDK 的 Xcode / Command Line Tools、Swift 6，以及 Apple Silicon Mac。运行目标仍为 macOS 14+。依赖源码已放在 Vendor 中。

```sh
zsh BuildSupport/build_app.sh
# 只读预览；不会开启硬件充电管理
open -n Dist/Aidente.app --args --ui-preview --preview-window

zsh BuildSupport/test_management_setup.sh
zsh BuildSupport/test_power_stream.sh
zsh BuildSupport/test_menu_item_ordering.sh
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

## 公开分发与更新

正式发行使用数字版本标签（例如 v6.2）、`Aidente-6.2-macOS-arm64.zip` 和 `SHA256SUMS-6.2.txt`，另提供拖入安装的 DMG。公开检查不保存或要求 GitHub 令牌。未验证签名身份的自行编译版本不能自动接受公开更新，可从发行页手动安装。自动替换与失败回滚仍需更多跨机型验收；建议公开分发使用 Developer ID 与 Apple 公证。

安装包不含签名私钥、GitHub 令牌或用于开发的证书文件。签名内附带的公开证书属于验证 App 身份所需的信息。快捷指令已有18个动作与3个快捷入口，宿主运行验收仍待执行。

## 卸载

在 Aidente 内打开关于 → 完全卸载 Aidente，核对范围后执行。应用会先尝试恢复充电默认值，再移除控制服务和本账户数据，把 App/历史等移入废纸篓；失败会保留必要组件供重试。下载的 DMG、源码、另存的诊断文件不属于自动清理范围。详见[卸载说明](Docs/UNINSTALL.md)。

## 来源与许可证

- 上游 Aidente：<https://github.com/buffoons8-sketch/Aidente>
- Stasis：<https://github.com/srimanachanta/Stasis>
- [GPL-3.0](LICENSE) 与 [第三方声明](THIRD_PARTY_NOTICES.md)
