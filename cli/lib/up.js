'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const ui = require('./ui');
const daemon = require('./daemon');
const menubar = require('./menubar');
const pair = require('./pair');
const { BRIDGE_PORT } = require('./platform');

const STATE_FILE = path.join(os.homedir(), '.clawix', 'state', 'bridge-status.json');
const NO_PEER_TIP_AFTER_MS = 30_000;

function readStatus() {
    try {
        const raw = fs.readFileSync(STATE_FILE, 'utf8');
        return JSON.parse(raw);
    } catch (e) {
        return null;
    }
}

function fmtAge(ms) {
    if (ms < 1000) return 'just now';
    const s = Math.floor(ms / 1000);
    if (s < 60) return `${s}s ago`;
    const m = Math.floor(s / 60);
    return `${m}m ago`;
}

async function run({ noWatch = false } = {}) {
    let started;
    try {
        started = daemon.start();
    } catch (e) {
        ui.fail(
            'bridge failed to start.',
            (e && e.message) || 'launchctl bootstrap exited with an error.',
            'run `clawix doctor` to diagnose the cause.'
        );
        process.exit(1);
    }

    const m = menubar.start();

    // Wait up to 2s for the daemon to bind the loopback port. If the
    // socket never opens, the user almost certainly has a configuration
    // error and we should surface that instead of a stale QR.
    const deadline = Date.now() + 2_000;
    let bound = false;
    while (Date.now() < deadline) {
        if (await daemon.probePort()) { bound = true; break; }
        await sleep(150);
    }
    if (!bound) {
        ui.fail(
            `bridge failed to bind 127.0.0.1:${BRIDGE_PORT} within 2s.`,
            'the LaunchAgent is loaded but the daemon never accepted connections.',
            'run `clawix doctor` to diagnose the cause and `clawix logs` to see why.'
        );
        process.exit(1);
    }

    pair.show({ json: false });

    if (m && m.skipped && m.reason) {
        process.stdout.write('\n' + ui.dim(`(menu bar: ${m.reason})`) + '\n');
    }

    if (noWatch) return;

    process.stdout.write('\n' + ui.dim('watching… press Ctrl+C to stop watching (the bridge keeps running).') + '\n\n');

    let tipShown = false;
    const startedAt = Date.now();
    const interval = setInterval(() => {
        const status = readStatus();
        if (!status) {
            ui.statusLine('  ' + ui.bullet('warn') + '  ' + ui.yellow('no heartbeat from daemon yet…'));
            return;
        }
        const last = Date.parse(status.lastHeartbeatAt || status.boundAt || '');
        const age = Number.isFinite(last) ? Date.now() - last : null;
        const stale = age !== null && age > 10_000;
        const peers = status.peerCount || 0;

        let line;
        if (stale) {
            line = '  ' + ui.bullet('fail') + '  '
                + ui.red(`daemon stale: last heartbeat ${age !== null ? fmtAge(age) : 'unknown'}`);
        } else if (peers > 0) {
            line = '  ' + ui.bullet('ok') + '  '
                + ui.green(`${peers} device${peers === 1 ? '' : 's'} paired`)
                + ui.dim(`  ·  bridge healthy${age !== null ? ' (heartbeat ' + fmtAge(age) + ')' : ''}`);
        } else {
            line = '  ' + ui.bullet('ok') + '  '
                + 'no devices paired yet'
                + ui.dim(`  ·  bridge healthy${age !== null ? ' (heartbeat ' + fmtAge(age) + ')' : ''}`);
        }
        ui.statusLine(line);

        if (!tipShown && peers === 0 && Date.now() - startedAt >= NO_PEER_TIP_AFTER_MS) {
            tipShown = true;
            ui.statusLineEnd();
            process.stdout.write('\n');
            process.stdout.write('  ' + ui.bullet('hint') + ' no devices paired in 30s. tips:\n');
            process.stdout.write('    ' + ui.dim('→') + ' is your iPhone on the same Wi-Fi as this Mac?\n');
            process.stdout.write('    ' + ui.dim('→') + ' is the Clawix iOS app open and on the pairing screen?\n');
            process.stdout.write('    ' + ui.dim('→') + ' is the macOS firewall allowing incoming connections? `clawix doctor`\n');
            process.stdout.write('\n');
        }
    }, 1000);

    return new Promise((resolve) => {
        const onSigint = () => {
            clearInterval(interval);
            ui.statusLineEnd();
            process.stdout.write('\n' + ui.dim('stopped watching; the bridge keeps running. use `clawix stop` to fully stop.') + '\n');
            process.removeListener('SIGINT', onSigint);
            resolve();
        };
        process.on('SIGINT', onSigint);
    });
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

module.exports = { run };
