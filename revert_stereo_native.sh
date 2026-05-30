#!/bin/bash
# One-shot revert: restore stock Discord.app from the full backup taken before the
# whole-bundle ad-hoc re-sign, and restore the original Developer-ID discord_voice.node.
# Use this if the stereo patch / ad-hoc signing causes any problem.
#
# After reverting: stereo is GONE, but screenshare + push notifications + autofill are
# back to stock, and Discord is fully Developer-ID signed again.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# newest full app backup
FULL="$(ls -d "$HERE"/_DISCORD_APP_FULL_BACKUP_* 2>/dev/null | sort | tail -1)"
[ -n "$FULL" ] && [ -d "$FULL/Discord.app" ] || { echo "ERROR: no _DISCORD_APP_FULL_BACKUP_*/Discord.app found"; exit 1; }
echo "Restoring app from: $FULL"

# original Developer-ID voice module backup
NODE_BAK="$(ls "$HERE"/_discord_voice_NODE_backup_*/discord_voice.node 2>/dev/null | sort | tail -1)"
LIVE_NODE="$(/usr/bin/find "$HOME/Library/Application Support/discord" -maxdepth 4 -name discord_voice.node -path '*modules/discord_voice/*' 2>/dev/null | sort | tail -1)"

# quit Discord
osascript -e 'quit app "Discord"' 2>/dev/null || true
for _ in 1 2 3 4 5; do pgrep -x Discord >/dev/null 2>&1 || break; sleep 1; done
pkill -9 -f "/Applications/Discord.app/Contents" 2>/dev/null || true
sleep 1

# restore the app bundle (rsync --delete makes it byte-identical to the backup)
rsync -a --delete "$FULL/Discord.app/" "/Applications/Discord.app/"
echo "app restored."

# restore the stock voice module if we have the original
if [ -n "${NODE_BAK:-}" ] && [ -n "${LIVE_NODE:-}" ]; then
    cp -p "$NODE_BAK" "$LIVE_NODE"
    echo "voice module restored (stereo removed)."
else
    echo "NOTE: original discord_voice.node backup not found; module left as-is."
fi

# the restored app is Developer-ID again -> clear ad-hoc-era TCC grants
for s in ScreenCapture Camera Microphone; do tccutil reset "$s" com.hnc.Discord >/dev/null 2>&1 || true; done

codesign --verify --deep --strict /Applications/Discord.app && echo "stock seal OK"
echo "Done. Relaunch Discord and re-grant Screen Recording on first screenshare."
