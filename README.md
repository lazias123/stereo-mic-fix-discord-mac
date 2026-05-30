# Micro stéréo Discord 2026 (Apple Silicon) — Procédé complet

Discord encode déjà l'audio en stéréo (Opus `stereo:1`, `num_channels:2`), **mais** le module
natif WebRTC downmixe la capture 2ch → 1ch *avant* l'encodeur. Résultat : les autres entendent
du mono (L = R). Le fix demande deux couches : un plugin renderer **et** un patch du binaire natif.

---

## ✨ C'est quoi ?

Ton micro Discord transmet en **mono** (les autres t'entendent « plat »). Ce repo le fait passer
en **vrai stéréo** (gauche ≠ droite) — **sans casser le partage d'écran**. Sur **Mac Apple Silicon**.

👉 **Tu n'as rien besoin de connaître.** **Claude Code** fait tout et te guide pas à pas. Tu copies
un prompt, tu réponds à ses questions. C'est tout.

## 🚀 Démarrage rapide

| | Étape |
|:--:|---|
| 1️⃣ | Installe **Claude Code** → [claude.com/claude-code](https://claude.com/claude-code) |
| 2️⃣ | Mets le modèle **Opus** : tape `/model` → choisis **Opus** *(le seul qui réussit tout)* |
| 3️⃣ | Tape `/goal va au bout` *(empêche Claude d'abandonner — **essentiel**)* |
| 4️⃣ | Colle le **prompt** ci-dessous ⬇️ |
| 5️⃣ | Réponds à ses questions, suis ses instructions ✅ |

> ⚠️ Une étape coupe une sécurité de macOS (SIP/AMFI). **Claude te demandera ton accord avant**
> et t'expliquera le risque. C'est le prix pour avoir **stéréo + partage d'écran** ensemble.

### 📋 Le prompt à coller

```text
Je suis sur un Mac Apple Silicon. Objectif : faire transmettre mon micro Discord en
STÉRÉO sans casser le partage d'écran (Go Live). Le procédé complet est dans le
README.md de ce repo — lis-le d'abord en entier.

Résumé du fix (deux couches) :
1. Module natif : patcher discord_voice.node pour stopper le downmix 2ch→1ch de WebRTC
   (script reapply_stereo_native.sh : 4 patches localisés par signature d'octets, puis
   signature ad-hoc du module).
2. Renderer : le plugin Equicord src/equicordplugins/stereoMic patche getCodecOptions
   AU RUNTIME dans start() — micro (contexte "default") → channels:2 + stereo, et le
   contexte "stream" (Go Live) est ÉPARGNÉ pour que le partage d'écran reste OK.
Le module patché est ad-hoc : il ne se charge que si AMFI est désactivé (SIP off), ce
qui permet de garder Discord.app en Developer-ID intact → screenshare préservé.
Un périphérique d'entrée 2 CANAUX doit être sélectionné dans Discord (n'importe lequel :
interface/micro stéréo, ou un câble virtuel 2ch pour router une source stéréo).

IMPORTANT — je suis DÉBUTANT : explique chaque étape en mots simples (ce que tu fais et
pourquoi), vérifie le résultat après chaque étape, et avant de toucher à la sécurité macOS
(désactiver SIP puis AMFI), ARRÊTE-TOI et DEMANDE-MOI ma confirmation en m'expliquant
clairement le risque. Ne désactive rien sans mon accord explicite.

Étapes à exécuter :
1. Vérifie qu'Equicord est installé et injecté dans Discord (sinon guide-moi pour l'installer).
2. Copie le plugin src/equicordplugins/stereoMic dans mon arbre Equicord, puis build (pnpm build).
3. Lance reapply_stereo_native.sh pour patcher + signer discord_voice.node.
4. Guide-moi pas à pas pour :
   - désactiver SIP puis AMFI : Recovery → "csrutil disable", reboot, puis
     sudo nvram boot-args="amfi_get_out_of_my_way=1", reboot ;
   - sélectionner un périphérique d'entrée 2 CANAUX dans Discord → Réglages → Voix et
     vidéo → Périphérique d'entrée (un micro/interface stéréo, ou un câble virtuel 2ch
     comme BlackHole 2ch `brew install blackhole-2ch` si je veux router une source stéréo).
5. Vérifie le résultat dans ~/Library/Application Support/discord/logs/discord-webrtc_0 :
   SetRecordingChannels(2) qui reste, captured_audio_processor channels:2, et
   ConfigureStream num_channels:2 stereo:1.

Va au bout. Utilise tes outils et des sous-agents si besoin. Ne t'arrête pas tant que le
log ne montre pas 2 canaux en capture.
```

⚠️ Désactiver SIP + AMFI **réduit la sécurité de toute la machine** (voir plus bas). C'est le
prix pour avoir stéréo **et** screenshare ensemble. À faire en connaissance de cause.

---

## 🎁 Bonus — FollowVoiceUser « débridé »

Plugin Equicord pour **suivre quelqu'un en vocal** (quand il change de salon, tu le suis).
La version d'origine ne marche que pour tes **amis**. Cette version est **débridée** : tu peux
suivre **n'importe quel utilisateur**.

📄 `bonus/followVoiceUser/index.tsx` → à copier dans `src/equicordplugins/followVoiceUser/`
de ton Equicord, puis rebuild (`pnpm build`). Clic droit sur un user → « Follow ».

---

# 🔧 Détails techniques (optionnel)

*Pas besoin de lire ça pour répliquer — Claude s'en occupe. C'est ici pour comprendre comment
ça marche sous le capot.*

## Vérité terrain : le log WebRTC

```
~/Library/Application Support/discord/logs/discord-webrtc_0
```

Lignes clés à surveiller :
- `audio_device_buffer.cc: SetRecordingChannels(N)` — capture device
- `captured_audio_processor.cpp:132 … channels: N` — pré-APM (Discord)
- `audio_send_stream.cc: ConfigureStream … num_channels: 2 … stereo: 1` — encodeur Opus
- `echo_canceller3.cc:792: AEC3 created … num capture channels: N` — sous-module APM
- `audio_processing_impl.cc: ApplyConfig … multi_channel_capture: 0` — la config qui cause le downmix

## Couche 0 — Périphérique d'entrée 2 canaux (PRÉREQUIS)

Discord capture le nb de canaux du **device d'entrée**. « Défaut » / un micro mono = **1 canal**
→ tout le reste est inutile (L = R). Il faut sélectionner un **périphérique d'entrée 2 canaux**
(Réglages → Voix et vidéo → Périphérique d'entrée).

Selon ton but :
- **Transmettre une source stéréo** (musique, audio d'une app, mix stéréo) → route-la dans un
  câble audio virtuel **2 canaux** et choisis-le comme entrée. Sur macOS, un exemple gratuit est
  [BlackHole 2ch](https://existential.audio/blackhole/) (`brew install blackhole-2ch`) — mais
  c'est juste **un** moyen ; n'importe quel device 2ch convient.
- **Vrai micro / interface stéréo** → sélectionne-le directement.

Aucun device 2ch précis n'est imposé par ce repo ; seul le **nombre de canaux (2)** compte.

## Couche 1 — Plugin renderer (JS)

`src/equicordplugins/stereoMic/index.tsx`. Le patch **webpack** sur `getCodecOptions` ne
s'enregistre pas de façon fiable (le module codec charge avant `initPluginManager`). À la place,
le plugin patche **au runtime dans `start()`** le prototype de la connexion vocale :
`getCodecOptions` → pour le contexte micro (`context !== "stream"`), force
`audioEncoder.channels = 2` + `params {stereo:"1"}`. Le contexte **`"stream"` (Go Live) est
épargné** → le partage d'écran reste intact. `required: true` pour que `start()` tourne toujours.
**Nécessaire mais pas suffisant** : sans le patch natif, l'APM réeffondre en mono.

## Couche 2 — Patch natif `discord_voice.node`

Binaire **fat Mach-O** ; Apple Silicon exécute la slice **arm64**. Extraction pour analyse :
`lipo -thin arm64 discord_voice.node -output /tmp/dv_arm64.node`, désassemblage `objdump -d`.

### Cause racine (WebRTC `AudioProcessingImpl`)

`config_.pipeline.multi_channel_capture` (octet à `this+365`) est **false** (Discord le force).
Deux mécanismes downmixent alors la capture :

1. **Allocation** : le buffer capture est alloué avec le nb de canaux lu dans `this+680`
   (= `api_format` output channels, que Discord met à **1**) → buffer mono.
2. **Runtime** : `ProcessCaptureStreamLocked` appelle `AudioBuffer::set_num_channels(1)` à chaque frame.

Layout struct (offsets depuis `this`) :

| Offset | Champ | Valeur build |
|---|---|---|
| +365 | `multi_channel_capture` (config) | 0 (false) |
| +769 | `multi_channel_capture_support` | 1 (true par défaut) |
| +680 | proc/output StreamConfig num_channels | 1 |
| +656 | input StreamConfig num_channels | 2 |

### Les 4 patches (slice arm64)

| # | Fonction | Site (vaddr) | Avant → Après | Effet |
|---|---|---|---|---|
| 0 | `AudioDeviceMac::InitRecording` | — | force `_recChannels = 2` | Capture 2ch depuis le device |
| P1 | `InitializeLockedEv` (alloc buffer) | `0x23848c` | `ldr x4,[x19,#680]` → `mov x4,x2` (`645641f9`→`e40302aa`) | Buffer capture suit **input** channels (2), pas output (1) |
| P2 | `ProcessCaptureStreamLocked` | `0x23a5c4` | `tbnz w8,#0,…` → `b 0x23a5d4` (`88000037`→`04000014`) | Skip le `set_num_channels(1)` runtime |
| P3 | `num_proc_channels()` | `0x2399fc` | `mov w0,#1` → `b 0x239a04` (`20008052`→`02000014`) | Retourne le **vrai** count (vtable) |

**P3 est crucial** : tous les sous-modules APM (AEC3, NoiseSuppressor, GainController1/2,
HighPassFilter) lisent leur nb de canaux via `num_proc_channels()` (vtable slot #80). Sans P3 ils
s'initialisent en mono pendant que le buffer est en 2ch → mismatch / crash possible si l'utilisateur
active la suppression de bruit ou l'annulation d'écho.

### Chargement du module patché — AMFI off (PAS de re-sign du bundle)

Le module patché casse sa signature Developer-ID → re-signé **ad-hoc**. Mais macOS refuse de
charger un module ad-hoc dans le renderer Developer-ID (library validation du hardened runtime).

**Approches écartées** (toutes cassent le screenshare ou crashent) :
- Re-signer le helper renderer ad-hoc → seal du bundle cassé → macOS 15+/26 revalide le seal
  au moment de la capture → Go Live « the app doesn't have permission to record your screen ».
- Re-signer le main app ad-hoc seul → identité mixte → renderer crash (fatal native).
- Re-signer **tout** le bundle ad-hoc cohérent → seal valide mais renderer crash en boucle
  (interaction Electron Framework ad-hoc ↔ module natif), et perd notifs push/keychain.

**Solution retenue : désactiver AMFI** au niveau système. Discord.app reste **100% Developer-ID
intact** (seal valide → screenshare OK, TCC préservé), et l'AMFI-off laisse le module ad-hoc se
charger sans rien re-signer dans le bundle.

```bash
# en Recovery (maintenir power → Options → Terminal) :
csrutil disable
# puis après reboot, dans le terminal normal :
sudo nvram boot-args="amfi_get_out_of_my_way=1"
# reboot. Le module ad-hoc patché se charge maintenant dans le renderer Developer-ID.
codesign --remove-signature discord_voice.node && codesign --force --sign - discord_voice.node
```

⚠️ **Sécurité** : SIP off + AMFI off réduit la protection de **toute la machine** (n'importe
quel binaire non signé peut charger des libs non signées). C'est le prix pour avoir stéréo
**et** screenshare ensemble. Réactiver SIP/AMFI → la stéréo casse (le module ad-hoc ne charge plus).

TCC : inchangé, l'app reste Developer-ID donc les grants (micro/écran) persistent.

### Persistance

`reapply_stereo_native.sh` réapplique les 4 patches natifs + re-signe le module ad-hoc
(**sans toucher** au bundle Discord.app, qui reste Developer-ID). Sites localisés par
**signature d'octets unique** → survit aux MAJ Discord tant que le code WebRTC est inchangé.
Idempotent (re-run = « already patched »). Le plugin renderer persiste via le build Equicord.
À relancer après chaque MAJ Discord (le module est re-téléchargé propre).

## Config complète (récap — pour refaire)

1. **SIP + AMFI off** (Recovery `csrutil disable` + `nvram boot-args=amfi_get_out_of_my_way=1`).
2. **Discord.app reste Developer-ID** (rien re-signé dans le bundle → screenshare OK).
3. **`discord_voice.node`** : 4 patches (InitRec+P1/P2/P3) + ad-hoc signé → `reapply_stereo_native.sh`.
4. **Plugin StereoMic** (`required:true`) : patch runtime de `getCodecOptions` dans `start()`,
   micro→2ch, `"stream"` épargné (screenshare safe). Buildé dans Equicord.
5. **Périphérique d'entrée 2 canaux** (micro/interface stéréo, ou câble virtuel 2ch type BlackHole), pas « Défaut ».

## Validation (preuves)

- **Submodules OFF** : encoder `2ch/stereo:1`, capture 2ch continue, 0 crash, paquets envoyés OK.
- **Submodules ON** (NoiseSuppression + EchoCancel + AGC) : `AEC3 … num capture channels: 2`,
  0 crash, audio fluide → pipeline **cohérent en multichannel**.
- **2 agents RE indépendants** : (1) aucun mismatch canaux — tous les sous-modules clé sur slot #80
  (= `num_proc_channels` patché) ; (2) le patch 3-sites est l'approche la plus sûre (forcer +365 ou
  +680 serait pire).
- **Confirmation auditive** : les potes entendent du vrai stéréo (L ≠ R).
