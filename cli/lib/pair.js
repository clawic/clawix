'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const qr = require('./qr');
const ui = require('./ui');
const { BRIDGE_PORT } = require('./platform');

const PLIST_BUDDY = '/usr/libexec/PlistBuddy';
const PREFS_PATH = path.join(os.homedir(), 'Library', 'Preferences', 'clawix.bridge.plist');

function readKey(key) {
    if (!fs.existsSync(PREFS_PATH)) return null;
    try {
        const out = execFileSync(PLIST_BUDDY, ['-c', `Print :${key}`, PREFS_PATH], {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'ignore']
        }).trim();
        return out || null;
    } catch (e) {
        return null;
    }
}

function detectLanIPv4() {
    const interfaces = os.networkInterfaces();
    for (const name of ['en0', 'en1']) {
        const list = interfaces[name];
        if (!list) continue;
        for (const entry of list) {
            if (entry.family === 'IPv4' && !entry.internal && !entry.address.startsWith('169.254.')) {
                return entry.address;
            }
        }
    }
    return null;
}

function detectTailscaleIPv4() {
    const interfaces = os.networkInterfaces();
    for (const [name, list] of Object.entries(interfaces)) {
        if (!name.startsWith('utun')) continue;
        for (const entry of list) {
            if (entry.family !== 'IPv4') continue;
            const parts = entry.address.split('.').map((p) => parseInt(p, 10));
            if (parts.length === 4 && parts[0] === 100 && parts[1] >= 64 && parts[1] <= 127) {
                return entry.address;
            }
        }
    }
    return null;
}

function readPairingPayload() {
    const bearer = readKey('ClawixBridge.Bearer.v1');
    const shortCode = readKey('ClawixBridge.ShortCode.v1');
    if (!bearer) return null;
    const lan = detectLanIPv4();
    const tail = detectTailscaleIPv4();
    return {
        v: 1,
        host: lan || '0.0.0.0',
        port: BRIDGE_PORT,
        token: bearer,
        hostDisplayName: os.hostname(),
        shortCode: shortCode || null,
        tailscaleHost: tail || null
    };
}

function publicPairingPayload(payload, { includeShortCode = true } = {}) {
    const out = {
        v: payload.v,
        host: payload.host,
        port: payload.port,
        token: payload.token,
        hostDisplayName: payload.hostDisplayName
    };
    if (includeShortCode && payload.shortCode) out.shortCode = payload.shortCode;
    if (payload.tailscaleHost) out.tailscaleHost = payload.tailscaleHost;
    return out;
}

function show({ json = false } = {}) {
    const payload = readPairingPayload();
    if (!payload) {
        ui.fail(
            'pairing token not found.',
            'the bridge daemon has not generated a pairing token yet.',
            'start it with `clawix start`, then run `clawix pair` again.'
        );
        process.exit(1);
    }

    if (json) {
        const out = publicPairingPayload(payload);
        process.stdout.write(JSON.stringify(out) + '\n');
        return;
    }

    ui.section('clawix bridge ready');
    process.stdout.write('  ' + ui.dim('on lan      ') + ' ' + payload.host + ':' + payload.port + '\n');
    if (payload.tailscaleHost) {
        process.stdout.write('  ' + ui.dim('on tailscale') + ' ' + payload.tailscaleHost + '\n');
    }

    ui.section('scan with the Clawix iOS app');
    // shortCode is intentionally omitted from the QR. iOS ignores it on
    // the scan path (the long token is what authenticates), and
    // dropping it knocks ~26 bytes off the payload, so the QR fits in a
    // smaller version and therefore in narrower terminal windows.
    const qrJson = JSON.stringify(publicPairingPayload(payload, { includeShortCode: false }));
    qr.generate(qrJson, { small: true });

    if (payload.shortCode) {
        ui.section('or paste this short code in the iOS app');
        process.stdout.write('  ' + ui.bold(payload.shortCode) + '\n');
    }
}

module.exports = { show, readPairingPayload, publicPairingPayload };
