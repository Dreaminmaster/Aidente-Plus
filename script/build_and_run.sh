#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
mode=${1:-run}
# Only stop this checkout's preview process, never the installed battery manager.
preview_binary="$project_dir/Dist/Aidente.app/Contents/MacOS/Aidente"
for app_pid in $(pgrep -f "$preview_binary --ui-preview" || true); do
    kill "$app_pid"
done
zsh BuildSupport/build_app.sh
if [[ "$mode" == "--build-only" ]]; then exit 0; fi
case "$mode" in
    run|--verify)
        /usr/bin/open -n Dist/Aidente.app --args --ui-preview --settings-tab=menubar
        if [[ "$mode" == "--verify" ]]; then
            sleep 2
            pgrep -f "$preview_binary --ui-preview" >/dev/null
        fi
        ;;
    --ux-preview)
        /usr/bin/open -n Dist/Aidente.app --args --ui-preview --settings-tab=charging
        ;;
    --features-preview)
        /usr/bin/open -n Dist/Aidente.app --args --ui-preview --settings-tab=overview --dump-preview-metrics="$project_dir/Dist/preview-metrics.json"
        ;;
    --uninstall-preview)
        /usr/bin/open -n Dist/Aidente.app --args --ui-preview --settings-tab=about
        ;;
    --debug) lldb -- "$preview_binary" --ui-preview --settings-tab=menubar ;;
    --logs|--telemetry)
        /usr/bin/open -n Dist/Aidente.app --args --ui-preview --settings-tab=menubar
        /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.aidente.app"'
        ;;
    *) print -u2 'usage: script/build_and_run.sh [run|--verify|--debug|--logs|--telemetry|--build-only|--uninstall-preview|--features-preview|--ux-preview]'; exit 2 ;;
esac
