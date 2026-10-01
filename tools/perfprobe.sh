#!/usr/bin/env bash
# Quick realtime perf probe for the builder: tools/perfprobe.sh LABEL [game args...]
cd "$(dirname "$0")/.." || exit 1
G=/c/Users/stewa/AppData/Local/Microsoft/WinGet/Links/godot_console.exe
OUT="${TEMP:-/tmp}/perf_$1.json"; shift
"$G" --path game --resolution 2560x1440 -- --seed=4242 --perf="$OUT" --duration=26 "$@" >/dev/null 2>&1
python -c "import json,sys; d=json.load(open(sys.argv[1])); print(sys.argv[2], d['avg_fps'], d['low_1pct_fps'], d['avg_gpu_ms'])" "$OUT" "$*"
