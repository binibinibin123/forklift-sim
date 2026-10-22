#!/bin/bash
# 컨테이너용 스크린샷: tools/shot.sh OUT scene=cab stop=3 [W H]
# 예: tools/shot.sh /tmp/a.png scene=menu
OUT=$1; shift
W=${W:-1560}; H=${H:-720}
G=${GODOT:-/tmp/claude-0/godot/Godot_v4.7.2-stable_linux.x86_64}
DISP=:7$(( (W % 7) ))
if ! pgrep -f "Xvfb $DISP" >/dev/null; then Xvfb $DISP -screen 0 ${W}x${H}x24 >/dev/null 2>&1 & sleep 1; fi
cd "$(dirname "$0")/.."
DISPLAY=$DISP timeout 120 "$G" --path . --rendering-method forward_plus --resolution ${W}x${H} --audio-driver Dummy -- shot=$OUT "$@" 2>&1 | grep -viE "^$|vulkan|xdg|WARNING" | head -20
ls -la "$OUT" 2>/dev/null | awk '{print $5, $9}'
