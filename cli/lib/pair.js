'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');

const qr = require('./qr');
const ui = require('./ui');
const { BRIDGE_PORT } = require('./platform');

const QR_PNG_PATH = path.join(os.homedir(), '.clawix', 'state', 'pair-qr.png');

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
        macName: os.hostname(),
        shortCode: shortCode || null,
        tailscaleHost: tail || null
    };
}

function show({ json = false } = {}) {
    const payload = readPairingPayload();
    if (!payload) {
        ui.fail(
            'pairing token not found.',
            'the bridge daemon has not generated a pairing bearer yet.',
            'start it with `clawix start`, then run `clawix pair` again.'
        );
        process.exit(1);
    }

    if (json) {
        const out = { v: payload.v, host: payload.host, port: payload.port, token: payload.token, macName: payload.macName };
        if (payload.shortCode) out.shortCode = payload.shortCode;
        if (payload.tailscaleHost) out.tailscaleHost = payload.tailscaleHost;
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
    // the scan path (the long bearer is what authenticates), and
    // dropping it knocks ~26 bytes off the payload, so the QR fits in a
    // smaller version and therefore in narrower terminal windows.
    const qrJson = JSON.stringify({
        v: payload.v,
        host: payload.host,
        port: payload.port,
        token: payload.token,
        macName: payload.macName,
        tailscaleHost: payload.tailscaleHost || undefined
    });
    qr.generate(qrJson, { small: true });

    // Always write a PNG copy and auto-open it on macOS. Terminal QRs
    // depend on font and theme (they render inverted on light themes,
    // for example) and the PNG side-steps both. Opening it in Preview
    // is the bulletproof scan path.
    try {
        fs.mkdirSync(path.dirname(QR_PNG_PATH), { recursive: true });
        fs.writeFileSync(QR_PNG_PATH, qr.toPng(qrJson));
        if (process.platform === 'darwin' && process.stdout.isTTY) {
            spawn('open', [QR_PNG_PATH], { detached: true, stdio: 'ignore' }).unref();
            process.stdout.write('\n  ' + ui.dim('png  ') + ' opened in Preview · ' + QR_PNG_PATH + '\n');
        } else {
            process.stdout.write('\n  ' + ui.dim('png  ') + ' ' + QR_PNG_PATH + '\n');
        }
    } catch (e) {
        // Non-fatal; the in-terminal QR is still there.
    }

    if (payload.shortCode) {
        ui.section('or paste this short code in the iOS app');
        process.stdout.write('  ' + ui.bold(payload.shortCode) + '\n');
    }
}

module.exports = { show, readPairingPayload };
