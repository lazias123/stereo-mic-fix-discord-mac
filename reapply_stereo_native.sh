#!/bin/bash
# Re-apply the StereoMic native patches after a Discord update wipes discord_voice.node.
#
# FINAL working config (stereo + screenshare together):
#   - Discord.app stays untouched Developer-ID  -> valid bundle seal -> screenshare works.
#   - discord_voice.node is byte-patched + ad-hoc signed.
#   - SIP + AMFI are disabled (boot-arg amfi_get_out_of_my_way=1) so the ad-hoc/patched
#     module loads into the Developer-ID renderer WITHOUT re-signing the app (which would
#     break the seal and kill Go Live). This is the trade that lets both features coexist.
#   - The renderer codec side is handled by the StereoMic plugin's start() runtime patch
#     (built into Equicord), NOT by this script.
#   - A 2-channel input device must be selected in Discord (any stereo mic/interface, or a
#     2ch virtual cable like BlackHole). "Default"/a mono mic yields mono no matter what.
#
# The 4 native patches (WebRTC AudioProcessingImpl / AudioDeviceMac, arm64 slice):
#   InitRecording  AudioDeviceMac::InitRecording   -> force _recChannels = 2
#   P1 alloc       InitializeLocked() capture buf  -> ldr x4,[x19,#680] => mov x4,x2
#                  (capture AudioBuffer channels follow INPUT channels, not the
#                   mono api_format output channel count)
#   P2 downmix     ProcessCaptureStreamLocked      -> skip set_num_channels(1)
#                  (never collapse the capture buffer to mono at runtime)
#   P3 num_proc    num_proc_channels()             -> return real (vtable) count
#
# Sites are located by unique byte SIGNATURE (not a hardcoded offset), so this survives
# Discord version bumps as long as the surrounding WebRTC code is unchanged.
#
# Revert: restore _dv_LIVE_*backup*.node or _discord_voice_NODE_backup_*/discord_voice.node
# over the live module, re-sign ad-hoc, relaunch.
set -euo pipefail

DISCORD_VER_DIR="$HOME/Library/Application Support/discord"

# AMFI must be off, otherwise the patched ad-hoc module will not load.
if ! nvram boot-args 2>/dev/null | grep -q "amfi_get_out_of_my_way=1"; then
    echo "WARNING: amfi_get_out_of_my_way=1 not set in boot-args."
    echo "         The patched module will NOT load. Disable SIP (Recovery: csrutil disable)"
    echo "         then: sudo nvram boot-args=\"amfi_get_out_of_my_way=1\" and reboot."
fi

# locate the active discord_voice module (newest version dir that has it)
LIVE_NODE="$(/usr/bin/find "$DISCORD_VER_DIR" -maxdepth 4 -name discord_voice.node -path '*modules/discord_voice/*' 2>/dev/null | sort | tail -1)"
[ -n "$LIVE_NODE" ] || { echo "ERROR: discord_voice.node not found under $DISCORD_VER_DIR"; exit 1; }
echo "Target module: $LIVE_NODE"

# quit Discord
osascript -e 'quit app "Discord"' 2>/dev/null || true
for _ in 1 2 3 4 5; do pgrep -x Discord >/dev/null 2>&1 || break; sleep 1; done
pkill -9 -f "/Applications/Discord.app/Contents" 2>/dev/null || true
sleep 1

# back up the live module before touching it
cp -p "$LIVE_NODE" "$(dirname "$0")/_dv_LIVE_prepatch_backup_$(date +%Y%m%d_%H%M%S).node"

# signature-based patcher
python3 - "$LIVE_NODE" <<'PY'
import sys
path = sys.argv[1]

# (name, orig_window_hex, patched_window_hex)
PATCHES = [
    ("InitRecording",
     "68ea47391f09007161000054684e19b910000014",
     "4800805268ea0739684e19b9110000141f2003d5"),
    # P1 ldr x4,[x19,#680] (645641f9) -> mov x4,x2 (e40302aa)
    ("P1_alloc",
     "624a41f963e283b9645641f965a282b9e60304aa",
     "624a41f963e283b9e40302aa65a282b9e60304aa"),
    # P2 tbnz w8,#0,skip (88000037) -> b skip (04000014)
    ("P2_downmix",
     "693641f9a90000b488000037e00314aa21008052",
     "693641f9a90000b404000014e00314aa21008052"),
    # P3 mov w0,#1 (20008052) -> b vtable (02000014)
    ("P3_nproc",
     "810000546800003720008052c0035fd6080040f9",
     "810000546800003702000014c0035fd6080040f9"),
]

with open(path, "r+b") as f:
    data = f.read()
    plan = []
    for name, orig_hex, new_hex in PATCHES:
        orig = bytes.fromhex(orig_hex)
        new  = bytes.fromhex(new_hex)
        if data.count(new) >= 1 and data.count(orig) == 0:
            print(f"[skip] {name}: already patched")
            continue
        n = data.count(orig)
        if n == 0:
            print(f"[ABORT] {name}: signature not found (Discord changed?)")
            sys.exit(1)
        if n > 1:
            print(f"[ABORT] {name}: signature not unique ({n} matches)")
            sys.exit(1)
        plan.append((name, data.find(orig), orig, new))
    for name, off, orig, new in plan:
        f.seek(off); f.write(new)
        print(f"[ok] {name} @ {hex(off)}")
print("Native patches applied.")
PY

# ad-hoc sign the patched module (AMFI-off lets it load; signing keeps things tidy)
codesign --remove-signature "$LIVE_NODE" 2>/dev/null || true
codesign --force --sign - "$LIVE_NODE"
codesign -v "$LIVE_NODE" && echo "module sig OK"

# Discord.app is intentionally NOT touched: it stays Developer-ID with a valid seal,
# so Screen Recording / Go Live keep working and TCC grants are preserved.

echo "Done. Relaunch Discord."
echo "Reminders: keep a 2-channel input device selected; AMFI must stay off."
