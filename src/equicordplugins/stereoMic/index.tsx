/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { definePluginSettings } from "@api/Settings";
import { EquicordDevs } from "@utils/constants";
import { findStoreLazy } from "@webpack";
import definePlugin, { makeRange, OptionType } from "@utils/types";

const MediaEngineStore = findStoreLazy("MediaEngineStore");

const settings = definePluginSettings({
    stereo: {
        type: OptionType.BOOLEAN,
        description: "Transmit your microphone in stereo. Rejoin the voice channel for changes to apply.",
        default: true
    },
    voiceBitrate: {
        type: OptionType.SLIDER,
        description: "Microphone bitrate in kbps. Higher sounds better but uses more bandwidth.",
        markers: makeRange(8, 512, 8),
        default: 128,
        stickToMarkers: true
    }
});

let pollInterval: number | undefined;

export default definePlugin({
    name: "StereoMic",
    description: "Transmit your microphone in stereo with a configurable bitrate.",
    authors: [EquicordDevs.nobody],
    tags: ["Voice"],
    required: true,
    settings,

    // Runtime patch of the voice connection's codec builder. The webpack patch route is
    // unreliable here because the codec module loads before patches register, so we wrap
    // getCodecOptions on the connection prototype as soon as a connection exists. Only the
    // microphone ("default") context is touched; the Go Live ("stream") context keeps
    // Discord's behaviour so screen sharing is unaffected.
    patchConnectionProto() {
        const ME = MediaEngineStore?.getMediaEngine?.();
        const conn = ME?.connections && [...ME.connections][0];
        if (!conn) return false;
        const proto = Object.getPrototypeOf(conn);
        if (proto.__stereoMicPatched) return true;
        const original = proto.getCodecOptions;
        if (typeof original !== "function") return false;
        proto.getCodecOptions = function (this: { context?: string; }, ...args: unknown[]) {
            const res = original.apply(this, args);
            try {
                if (settings.store.stereo && this.context !== "stream" && res?.audioEncoder) {
                    res.audioEncoder.channels = 2;
                    res.audioEncoder.params = { ...res.audioEncoder.params, stereo: "1" };
                }
            } catch { /* leave codec untouched on any shape mismatch */ }
            return res;
        };
        proto.__stereoMicPatched = true;
        return true;
    },

    start() {
        if (this.patchConnectionProto()) return;
        pollInterval = setInterval(() => {
            if (this.patchConnectionProto()) {
                clearInterval(pollInterval);
                pollInterval = undefined;
            }
        }, 500) as unknown as number;
    },

    stop() {
        if (pollInterval !== undefined) {
            clearInterval(pollInterval);
            pollInterval = undefined;
        }
    }
});
