# Discord stereo microphone — Apple Silicon Mac

Discord already encodes audio in stereo (Opus `stereo:1`, `num_channels:2`), **but** the native
WebRTC module downmixes the 2ch capture to 1ch *before* the encoder. Result: everyone hears you
in mono (L = R). The fix needs two layers: a renderer plugin **and** a native binary patch.

---

## ✨ What is this?

Your Discord mic transmits in **mono** (others hear you "flat"). This repo makes it true
**stereo** (left ≠ right) — **without breaking screen sharing**. On **Apple Silicon Macs**.

👉 **You don't need to know anything.** **Claude Code** does everything and walks you through it
step by step. You paste a prompt, answer its questions. That's it.

> ### ⛔ Prerequisite — you need a real STEREO source
> A 2-channel input device is useless if the sound feeding it is mono. You need a genuinely
> **stereo input on your Mac**:
> - a **stereo microphone / audio interface** (already 2 channels), **or**
> - at minimum a **DAW** (Ableton, Reaper, FL Studio…) outputting a stereo signal, routed into
>   Discord through a **2-channel virtual audio cable** — on Mac: **BlackHole 2ch**
>   ([download](https://existential.audio/blackhole/) or `brew install blackhole-2ch`).
>
> A mono mic → stays mono, no matter the patches. Sort this out first.

## 🚀 Quick start

| | Step |
|:--:|---|
| 1️⃣ | Install **Claude Code** → [claude.com/claude-code](https://claude.com/claude-code) |
| 2️⃣ | Set the model to **Opus**: type `/model` → pick **Opus** *(the only one that pulls it off)* |
| 3️⃣ | Type `/goal go all the way` *(keeps Claude from giving up — **essential**)* |
| 4️⃣ | Paste the **prompt** below ⬇️ |
| 5️⃣ | Answer its questions, follow its instructions ✅ |

> ⚠️ One step turns off a macOS security feature (SIP/AMFI). **Claude will ask for your approval
> first** and explain the risk. That's the price for getting stereo **without breaking** screen sharing (which works by default and the naive patch breaks).

### 📋 The prompt to paste

```text
I'm on an Apple Silicon Mac. Goal: make my Discord microphone transmit in STEREO without
breaking screen sharing (Go Live). The full procedure is in this repo's README.md — read it
fully first.

Fix summary (two layers):
1. Native module: patch discord_voice.node to stop WebRTC's 2ch->1ch downmix
   (script reapply_stereo_native.sh: 4 patches located by byte signature, then ad-hoc
   sign the module).
2. Renderer: the Equicord plugin src/equicordplugins/stereoMic patches getCodecOptions
   AT RUNTIME in start() — mic ("default" context) -> channels:2 + stereo, while the
   "stream" (Go Live) context is LEFT ALONE so screen sharing keeps working.
The patched module is ad-hoc signed: it only loads if AMFI is disabled (SIP off), which
lets Discord.app stay Developer-ID intact -> screenshare preserved.
PREREQUISITE: I need a genuinely STEREO input source — either a stereo mic/interface, or a
DAW (Ableton/Reaper/FL Studio) whose stereo output is routed into a 2ch virtual cable. A mono
mic stays mono no matter what. Then a 2-CHANNEL input device must be selected in Discord.

IMPORTANT — I'm a BEGINNER: explain each step in plain words (what you do and why), verify
the result after each step, and before touching macOS security (disabling SIP then AMFI),
STOP and ASK me for confirmation, clearly explaining the risk. Don't disable anything
without my explicit OK.

Steps to run:
1. Check that Equicord is installed and injected into Discord (otherwise guide me to install it).
2. Copy the src/equicordplugins/stereoMic plugin into my Equicord tree, then build (pnpm build).
3. Run reapply_stereo_native.sh to patch + sign discord_voice.node.
4. Walk me through, step by step:
   - disabling SIP then AMFI: Recovery -> "csrutil disable", reboot, then
     sudo nvram boot-args="amfi_get_out_of_my_way=1", reboot;
   - selecting a 2-CHANNEL input device in Discord -> Settings -> Voice & Video ->
     Input Device (a stereo mic/interface, or a 2ch virtual cable like BlackHole 2ch
     `brew install blackhole-2ch` if I want to route a stereo source).
5. Verify the result in ~/Library/Application Support/discord/logs/discord-webrtc_0:
   SetRecordingChannels(2) that stays, captured_audio_processor channels:2, and
   ConfigureStream num_channels:2 stereo:1.

Go all the way. Use your tools and sub-agents if needed. Don't stop until the log shows
2 channels at capture.
```

⚠️ Disabling SIP + AMFI **lowers security for the whole machine** (see below). It's the price
to get stereo **without breaking** screen sharing. Do it knowingly.

---

## 🎁 Bonus — FollowVoiceUser (unrestricted)

Equicord plugin to **follow someone in voice** (when they move channels, you follow them).
The original only works for your **friends**. This version is **unrestricted**: you can follow
**any user**.

📄 `bonus/followVoiceUser/index.tsx` → copy it into `src/equicordplugins/followVoiceUser/` of
your Equicord tree, then rebuild (`pnpm build`). Right-click a user → "Follow".

---

# 🔧 Technical details (optional)

*You don't need to read this to replicate — Claude handles it. It's here to understand how it
works under the hood.*

## Ground truth: the WebRTC log

```
~/Library/Application Support/discord/logs/discord-webrtc_0
```

Key lines to watch:
- `audio_device_buffer.cc: SetRecordingChannels(N)` — capture device
- `captured_audio_processor.cpp:132 … channels: N` — pre-APM (Discord)
- `audio_send_stream.cc: ConfigureStream … num_channels: 2 … stereo: 1` — Opus encoder
- `echo_canceller3.cc:792: AEC3 created … num capture channels: N` — APM submodule
- `audio_processing_impl.cc: ApplyConfig … multi_channel_capture: 0` — the config that causes the downmix

## Layer 0 — 2-channel input device (PREREQUISITE)

Discord captures the channel count of the **input device**. "Default" / a mono mic = **1 channel**
→ everything else is pointless (L = R). You must select a **2-channel input device** (Settings →
Voice & Video → Input Device).

Depending on your goal:
- **A real stereo mic / interface** (already 2 channels) → select it directly.
- **Transmit a stereo source** (a DAW like Ableton / Reaper / FL Studio, music, an app's audio,
  a stereo mix) → route its stereo output into a **2-channel** virtual audio cable and pick that
  cable as input. On macOS, a free cable is
  [BlackHole 2ch](https://existential.audio/blackhole/) (`brew install blackhole-2ch`) — but that's
  just **one** option; any 2ch device works.

No specific 2ch device is required by this repo; only the **channel count (2)** matters.

### Example routing — DAW → Discord, with live monitoring

A real-world setup that sends a stereo signal to Discord **while still hearing yourself live**
(tested config behind this repo):

1. **Audio MIDI Setup** (macOS) → create a **Multi-Output Device** that combines **BlackHole 2ch**
   + your **headphones** (enable *Drift Correction* on the headphones, primary device = BlackHole,
   48 kHz). This plays your audio to Discord **and** your ears at the same time.
2. In your **DAW** (Ableton / Reaper / FL Studio) → Preferences → Audio:
   - **Input** = your audio interface / sound card (e.g. a 2-in/2-out USB interface),
   - **Output** = the Multi-Output Device you just created.
3. In **Discord** → Settings → Voice & Video → **Input Device = BlackHole 2ch**.

Result: your interface → DAW (stereo) → Multi-Output → headphones (live monitoring) **+**
BlackHole 2ch → Discord (stereo mic). Adjust buffer size in the DAW for low latency.

## Layer 1 — Renderer plugin (JS)

`src/equicordplugins/stereoMic/index.tsx`. The **webpack** patch on `getCodecOptions` doesn't
register reliably (the codec module loads before `initPluginManager`). Instead, the plugin patches
the voice connection prototype **at runtime in `start()`**: `getCodecOptions` → for the mic context
(`context !== "stream"`), it forces `audioEncoder.channels = 2` + `params {stereo:"1"}`. The
**`"stream"` (Go Live) context is left untouched** → screen sharing stays intact. `required: true`
so `start()` always runs. **Necessary but not sufficient**: without the native patch, the APM
collapses back to mono.

## Layer 2 — Native `discord_voice.node` patch

**Fat Mach-O** binary; Apple Silicon runs the **arm64** slice. Extract for analysis:
`lipo -thin arm64 discord_voice.node -output /tmp/dv_arm64.node`, disassemble with `objdump -d`.

### Root cause (WebRTC `AudioProcessingImpl`)

`config_.pipeline.multi_channel_capture` (byte at `this+365`) is **false** (Discord forces it).
Two mechanisms then downmix the capture:

1. **Allocation**: the capture buffer is allocated with the channel count read from `this+680`
   (= `api_format` output channels, which Discord sets to **1**) → mono buffer.
2. **Runtime**: `ProcessCaptureStreamLocked` calls `AudioBuffer::set_num_channels(1)` every frame.

Struct layout (offsets from `this`):

| Offset | Field | Build value |
|---|---|---|
| +365 | `multi_channel_capture` (config) | 0 (false) |
| +769 | `multi_channel_capture_support` | 1 (true by default) |
| +680 | proc/output StreamConfig num_channels | 1 |
| +656 | input StreamConfig num_channels | 2 |

### The 4 patches (arm64 slice)

| # | Function | Site (vaddr) | Before → After | Effect |
|---|---|---|---|---|
| 0 | `AudioDeviceMac::InitRecording` | — | force `_recChannels = 2` | Capture 2ch from the device |
| P1 | `InitializeLockedEv` (buffer alloc) | `0x23848c` | `ldr x4,[x19,#680]` → `mov x4,x2` (`645641f9`→`e40302aa`) | Capture buffer follows **input** channels (2), not output (1) |
| P2 | `ProcessCaptureStreamLocked` | `0x23a5c4` | `tbnz w8,#0,…` → `b 0x23a5d4` (`88000037`→`04000014`) | Skip the runtime `set_num_channels(1)` |
| P3 | `num_proc_channels()` | `0x2399fc` | `mov w0,#1` → `b 0x239a04` (`20008052`→`02000014`) | Return the **real** count (vtable) |

**P3 is crucial**: all APM submodules (AEC3, NoiseSuppressor, GainController1/2, HighPassFilter)
read their channel count via `num_proc_channels()` (vtable slot #80). Without P3 they initialize in
mono while the buffer is 2ch → mismatch / possible crash if the user enables noise suppression or
echo cancellation.

### Loading the patched module — AMFI off (NO bundle re-sign)

The patched module breaks its Developer-ID signature → re-signed **ad-hoc**. But macOS refuses to
load an ad-hoc module into the Developer-ID renderer (hardened-runtime library validation).

**Discarded approaches** (all break screenshare or crash):
- Re-sign the renderer helper ad-hoc → parent bundle seal broken → macOS 15+/26 revalidates the
  seal at capture time → Go Live "the app doesn't have permission to record your screen".
- Re-sign only the main app ad-hoc → mixed identity → renderer crash (fatal native).
- Re-sign the **whole** bundle ad-hoc consistently → valid seal but renderer crashes in a loop
  (ad-hoc Electron Framework ↔ native module interaction), and loses push notifications/keychain.

**Chosen solution: disable AMFI** system-wide. Discord.app stays **100% Developer-ID intact**
(valid seal → screenshare OK, TCC preserved), and AMFI-off lets the ad-hoc module load without
re-signing anything in the bundle.

```bash
# in Recovery (hold power -> Options -> Terminal):
csrutil disable
# then after reboot, in a normal terminal:
sudo nvram boot-args="amfi_get_out_of_my_way=1"
# reboot. The ad-hoc patched module now loads into the Developer-ID renderer.
codesign --remove-signature discord_voice.node && codesign --force --sign - discord_voice.node
```

⚠️ **Security**: SIP off + AMFI off lowers protection for the **whole machine** (any unsigned
binary can load unsigned libraries). It's the price for getting stereo **without breaking** screen sharing.
Re-enabling SIP/AMFI → stereo breaks (the ad-hoc module no longer loads).

TCC: unchanged — the app stays Developer-ID, so grants (mic/screen) persist.

### Persistence

`reapply_stereo_native.sh` re-applies the 4 native patches + re-signs the ad-hoc module
(**without touching** the Discord.app bundle, which stays Developer-ID). Sites are located by
**unique byte signature** → survives Discord updates as long as the WebRTC code is unchanged.
Idempotent (re-run = "already patched"). The renderer plugin persists via the Equicord build.
Re-run after each Discord update (the module is re-downloaded clean).

## Full config (recap — to redo)

1. **SIP + AMFI off** (Recovery `csrutil disable` + `nvram boot-args=amfi_get_out_of_my_way=1`).
2. **Discord.app stays Developer-ID** (nothing re-signed in the bundle → screenshare OK).
3. **`discord_voice.node`**: 4 patches (InitRec+P1/P2/P3) + ad-hoc signed → `reapply_stereo_native.sh`.
4. **StereoMic plugin** (`required:true`): runtime patch of `getCodecOptions` in `start()`,
   mic→2ch, `"stream"` left alone (screenshare safe). Built into Equicord.
5. **2-channel input device** (stereo mic/interface, or a 2ch virtual cable like BlackHole), not "Default".

## Validation (evidence)

- **Submodules OFF**: encoder `2ch/stereo:1`, capture stays 2ch, 0 crash, packets sent fine.
- **Submodules ON** (NoiseSuppression + EchoCancel + AGC): `AEC3 … num capture channels: 2`,
  0 crash, smooth audio → **consistent multichannel** pipeline.
- **2 independent RE agents**: (1) no channel mismatch — all key submodules on slot #80
  (= patched `num_proc_channels`); (2) the 3-site patch is the safest approach (forcing +365 or
  +680 would be worse).
- **Audible confirmation**: friends hear true stereo (L ≠ R).
