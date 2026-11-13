#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
destination=${1:-"$project_dir/Dist/Aidente-macOS27-with-uninstaller.dmg"}
if [[ -e "$destination" ]]; then
    print -u2 "Refusing to overwrite existing image: $destination"
    exit 1
fi
codesign --verify --deep --strict Dist/Aidente.app
staging_dir=$(mktemp -d /tmp/aidente-dmg.XXXXXX)
mount_dir=$(mktemp -d /tmp/aidente-dmg-check.XXXXXX)
mounted=0
cleanup() {
    if [[ "$mounted" == 1 ]]; then hdiutil detach "$mount_dir" >/dev/null || true; fi
    rm -rf -- "$staging_dir"
    rmdir "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT
ditto Dist/Aidente.app "$staging_dir/Aidente.app"
ln -s /Applications "$staging_dir/Applications"
cat > "$staging_dir/安装说明.txt" <<'TEXT'
Aidente · macOS 27 工作流补全测试版

安装：将 Aidente.app 拖到 Applications，推出磁盘映像，再从“应用程序”打开。

权限：查看电池信息不需要管理员权限；启用、修复或移除控制服务时由 macOS 系统弹窗请求管理员授权。通知与登录时启动可选。只有可选“合盖锁屏”需要辅助功能权限；普通监测和限充不需要。无需屏幕录制或完全磁盘访问权限。

界面：上限弹窗、底部自定义入口、小组件与曲线、三种布局、原生侧栏、三列仪表板、菜单栏项目目录与任务列表。旧自定义布局会保留；要恢复紧凑弹窗，打开“弹出窗口→在编辑模式下打开→添加→恢复默认布局”。

本轮补充：电源状态事件立即刷新、指示灯提示可跳转充电控制、滑条原生高光/状态组合/航海竖向边界、私有仓库发行页更新入口、所有运行App/仅高能耗范围切换、完整可滚动名单、按名称固定排序及鼠标停留时固定条目、跟随系统/浅色/深色外观、高能耗App近期用量平滑与延迟移除、当前/5/15/30分钟平均功率、曲线刻度开关、系统校准识别及满电后的单次恢复/继续策略、真实趋势保存与后台采样（最近有记录时长/实际过去时间可选）、窗口位置大小恢复、航海范围标记与低电量保护、系统充满时间只读接口。原生校准事件和硬件控制仍待实机验收；MagSafe线缆固件与综合能量影响仍有差异。

菜单栏：macOS 27/iOS 风格数字在电池内，旧 macOS 与状态样式数字在外；可切换读数图标，并选择右击动作。指示灯在“其他”页面的三项模式中管理。

功能：原生快捷指令 18 个动作、按电池/电源选择功耗模式、手动睡眠控制、高级睡眠选项、独立 MagSafe 灯光策略、计划模板与历史、更多仪表板组件和读数，以及重新绘制的菜单栏插头图形。
高功耗及 MagSafe 控制按机型能力开放。阻止闲置睡眠不能保证绕过强制睡眠或所有机型的合盖行为。

卸载：打开 Aidente → 设置 → 关于 → 完全卸载 Aidente…，核对范围后确认。
应用会先恢复默认充电控制，再移除后台服务及恢复备份、注销登录项、清除本账户设置，将历史、缓存和 App 移入废纸篓并退出。
恢复充电失败会停止卸载；其他步骤失败会保留 App 供重试。
下载的 DMG、源码、用户另存的诊断包和系统日志不会清理。不会改动官方 AlDente。

此版本没有 Developer ID 签名或 Apple 公证；首次打开可能受到系统拦截。
启用充电控制前请退出其他充电管理软件，避免争用。
这是独立开源测试版，与官方 AlDente Pro 仍有功能和外观差异。
完整卸载已通过模拟测试和预览检查，尚未在本机执行真正的管理员卸载验收。
TEXT
hdiutil create -volname 'Aidente Test' -srcfolder "$staging_dir" -format UDZO "$destination"
hdiutil verify "$destination"
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$destination"
mounted=1
codesign --verify --deep --strict "$mount_dir/Aidente.app"
test "$(readlink "$mount_dir/Applications")" = /Applications
cmp "$mount_dir/Aidente.app/Contents/Resources/install_local_control.sh" BuildSupport/install_local_control.sh
hdiutil detach "$mount_dir"
mounted=0
shasum -a 256 "$destination"
ls -lh "$destination"
