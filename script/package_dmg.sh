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
Aidente 6.2.3 · Apple Silicon / macOS 14+

安装：将 Aidente.app 拖入 Applications，推出磁盘映像，再从“应用程序”打开。

首次打开：查看电池信息无需授权。选择“启用电池管理”后，才安装限充和指示灯共用的后台服务，并由 macOS 请求管理员授权；“稍后，仅查看”不启用控制。

指示灯：未启用时也能选择模式。点击“启用并继续”，授权成功后才开启并应用选择；取消保持关闭。已启用后的普通切换不重复索要密码；服务缺失或更新时才需修复。

权限：普通限充不需要屏幕录制或完全磁盘访问。通知、登录时启动可选；仅可选“合盖锁屏”需要辅助功能。密码只在 macOS 系统窗口输入。

睡眠：新用户默认“保持当前充电策略”。“睡眠时暂停充电”需要明确选择；升级保留原设置。

更新：在“关于”检查公开 GitHub 发行版。自动检查由开关决定，安装前由你确认。应用不保存 GitHub 令牌或签名私钥。

卸载：Aidente → 关于 → 完全卸载。先恢复充电默认，再移除后台服务及应用数据，App/历史移到废纸篓；恢复失败会停止卸载。下载包、源码和另存的诊断包不自动删除，不改动官方 AlDente。

此包使用本机开发签名，未 Apple 公证。支持情况依 MacBook 型号与固件而异，不承诺全M系列硬件控制能力一致。完整校准和快捷指令宿主验收仍暂缓。
此为独立开源项目，与 AppHouseKitchen 无隶属关系。
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
