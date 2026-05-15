'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ui = require('./ui');
const diag = require('./diagnostics');
const { resolveBridged, resolveMenubar } = require('./binary');
const { BIN_DIR, LAUNCH_AGENTS_DIR, BRIDGE_LABEL, BRIDGE_PORT, APP_BUNDLE_PATH, BRIDGE_STATUS_FILE, Env } = require('./platform');

function check(name, level, message, fix) {
    return { name, level, message, fix: fix || null };
}

function run() {
    const checks = [];

    if (process.platform !== 'darwin' && process.platform !== 'win32') {
        checks.push(check('platform', 'fail', `running on ${process.platform}; clawix requires macOS or Windows.`, 'install on a supported host.'));
        return checks;
    }
    checks.push(check('platform', 'ok', `${process.platform === 'win32' ? 'Windows' : 'macOS'} (${process.platform})`, null));

    if (process.platform === 'win32') {
        // Windows-specific check path. Heartbeat lives at the same logical
        // location (~/.clawix/state/bridge-status.json) but resolved via
        // %USERPROFILE%; mac-specific things (codesign, plist, launchctl)
        // are skipped.
        const stateFile = BRIDGE_STATUS_FILE;
        if (!fs.existsSync(stateFile)) {
            checks.push(check('heartbeat', 'warn',
                'bridge-status.json missing on Windows.',
                'install the daemon: `clawix install` or run Clawix-Setup.msix.'));
        } else {
            try {
                const j = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
                const last = Date.parse(j.lastHeartbeatAt || '');
                const age = Number.isFinite(last) ? Date.now() - last : Infinity;
                checks.push(check('heartbeat', age > 10_000 ? 'fail' : 'ok',
                    age > 10_000 ? `last daemon heartbeat ${Math.round(age / 1000)}s ago.`
                                 : `heartbeat fresh (${Math.round(age / 1000)}s ago)`,
                    age > 10_000 ? 'restart Clawix from the system tray, or `clawix restart`.' : null));
            } catch (_) {
                checks.push(check('heartbeat', 'fail', 'bridge-status.json is not valid JSON.', 'restart the daemon.'));
            }
        }
        const localApp = path.join(process.env[Env.localAppData] || os.homedir(), 'Clawix', 'clawix-bridge.exe');
        if (!fs.existsSync(localApp)) {
            checks.push(check('clawix-bridge-binary', 'warn',
                `clawix-bridge.exe not found at ${localApp}.`,
                'install via `clawix install` (downloads the signed MSIX).'));
        } else {
            checks.push(check('clawix-bridge-binary', 'ok', `clawix-bridge.exe at ${localApp}`, null));
        }
        return checks;
    }

    const macos = diag.macosVersion();
    if (!macos) {
        checks.push(check('macos-version', 'warn', 'sw_vers did not return a version.', 'try `sw_vers -productVersion` manually.'));
    } else if (macos.major < 14) {
        checks.push(check('macos-version', 'fail', `macOS ${macos.full} (need 14 Sonoma or later).`, 'upgrade macOS or install on a newer Mac.'));
    } else {
        checks.push(check('macos-version', 'ok', `macOS ${macos.full}`, null));
    }

    const codex = diag.codexInPath();
    if (!codex) {
        checks.push(check('codex-cli', 'fail',
            'codex CLI not found in PATH or known locations.',
            'install with `npm install -g @openai/codex`.'));
    } else {
        checks.push(check('codex-cli', 'ok', `codex at ${codex}`, null));
    }

    const bridgedPath = resolveBridged();
    const menubarPath = resolveMenubar();

    const bridgedSig = diag.verifyCodesign(bridgedPath);
    if (!bridgedSig.exists) {
        checks.push(check('clawix-bridge-binary', 'fail',
            `clawix-bridge not found at ${bridgedPath}.`,
            'reinstall with `npm install -g clawix --force` or rerun `bash scripts-dev/cli-link.sh` for dev.'));
    } else if (!bridgedSig.valid) {
        checks.push(check('clawix-bridge-binary', 'fail',
            `clawix-bridge failed codesign --verify at ${bridgedPath}.`,
            'reinstall to repair the signature.'));
    } else {
        checks.push(check('clawix-bridge-binary', 'ok', `clawix-bridge signed (${bridgedPath})`, null));
    }

    const menubarSig = diag.verifyCodesign(menubarPath);
    if (!menubarSig.exists) {
        checks.push(check('clawix-menubar-binary', 'warn',
            `clawix-menubar not found at ${menubarPath}.`,
            'reinstall to get the menu bar helper. the bridge still works without it.'));
    } else if (!menubarSig.valid) {
        checks.push(check('clawix-menubar-binary', 'fail',
            `clawix-menubar failed codesign --verify at ${menubarPath}.`,
            'reinstall to repair the signature.'));
    } else {
        checks.push(check('clawix-menubar-binary', 'ok', 'clawix-menubar signed', null));
    }

    const listeners = diag.lsofPort(BRIDGE_PORT);
    if (listeners.length === 0) {
        checks.push(check('port', 'warn', `nothing is listening on port ${BRIDGE_PORT}.`,
            'start the bridge with `clawix start`.'));
    } else {
        // Prefer matching by PID: the daemon writes its PID into the
        // heartbeat file at startup, so anything listening with that
        // exact PID is ours. Falls back to a name prefix when the
        // heartbeat is missing (post-uninstall, pre-start). Note that
        // `lsof` truncates the command column to ~9 chars so we cannot
        // match the full literal `clawix-bridge`.
        const heartbeat = require('./daemon').readHeartbeat();
        const ourPid = heartbeat ? String(heartbeat.pid) : null;
        const isOurs = listeners.some((l) =>
            (ourPid && l.pid === ourPid) || /^clawix-?br/i.test(l.command || ''));
        if (isOurs) {
            checks.push(check('port', 'ok', `clawix-bridge listening on port ${BRIDGE_PORT}`, null));
        } else {
            const other = listeners[0];
            checks.push(check('port', 'fail',
                `port ${BRIDGE_PORT} is held by ${other.command} (pid ${other.pid}).`,
                'stop that process; clawix needs port 24080 free.'));
        }
    }

    const plistPath = path.join(LAUNCH_AGENTS_DIR, `${BRIDGE_LABEL}.plist`);
    const plist = diag.plutilLint(plistPath);
    if (!plist.exists) {
        checks.push(check('launchagent-plist', 'warn',
            `launchd plist missing at ${plistPath}.`,
            'register it with `clawix start`.'));
    } else if (!plist.valid) {
        checks.push(check('launchagent-plist', 'fail',
            `launchd plist at ${plistPath} is invalid.`,
            'remove it (`clawix uninstall`) and re-register with `clawix start`.'));
    } else {
        checks.push(check('launchagent-plist', 'ok', `${plistPath}`, null));
    }

    const lc = diag.launchctlPrint(BRIDGE_LABEL);
    if (!lc.loaded) {
        checks.push(check('launchagent', 'warn',
            `${BRIDGE_LABEL} not loaded in launchd.`,
            'load it with `clawix start`.'));
    } else if (lc.state === 'running') {
        checks.push(check('launchagent', 'ok', `${BRIDGE_LABEL} running (program ${lc.program || '?'})`, null));
    } else {
        checks.push(check('launchagent', 'fail',
            `${BRIDGE_LABEL} state=${lc.state}, last exit=${lc.lastExitCode ?? 'n/a'}.`,
            'inspect with `clawix logs` and restart with `clawix restart`.'));
    }

    const lan = diag.lanIpv4();
    if (!lan) {
        checks.push(check('lan-ipv4', 'warn',
            'no LAN IPv4 detected on en0/en1.',
            'connect to a Wi-Fi or Ethernet network so the iPhone can reach the bridge.'));
    } else {
        checks.push(check('lan-ipv4', 'ok', `${lan.iface} ${lan.address}`, null));
    }

    const tail = diag.tailscaleIpv4();
    if (tail) {
        checks.push(check('tailscale', 'ok', `${tail.iface} ${tail.address}`, null));
    } else {
        checks.push(check('tailscale', 'ok', 'not detected (optional)', null));
    }

    if (bridgedSig.exists) {
        const fw = diag.firewallBlocked(bridgedPath);
        if (fw.applicable && fw.blocked === true) {
            checks.push(check('firewall', 'fail',
                'macOS firewall is blocking incoming connections to clawix-bridge.',
                'open System Settings → Network → Firewall → Options, find clawix-bridge and switch it to "Allow incoming connections".'));
        } else if (fw.applicable && fw.blocked === false) {
            checks.push(check('firewall', 'ok', 'macOS firewall allows clawix-bridge', null));
        } else {
            checks.push(check('firewall', 'ok', 'firewall status unavailable (likely off)', null));
        }
    }

    const prefs = path.join(os.homedir(), 'Library', 'Preferences', 'clawix.bridge.plist');
    const bearer = diag.plistBuddyRead(prefs, 'ClawixBridge.Bearer.v1');
    const shortCode = diag.plistBuddyRead(prefs, 'ClawixBridge.ShortCode.v1');
    if (!bearer) {
        checks.push(check('pairing-bearer', 'warn',
            'pairing bearer not yet generated.',
            'start the bridge with `clawix start`; the daemon eagerly materialises it.'));
    } else {
        checks.push(check('pairing-bearer', 'ok', 'bearer materialised in clawix.bridge suite', null));
    }
    if (!shortCode) {
        checks.push(check('pairing-shortcode', 'warn',
            'pairing short code not yet generated.',
            'start the bridge with `clawix start`.'));
    } else {
        checks.push(check('pairing-shortcode', 'ok', `short code ${shortCode}`, null));
    }

    if (fs.existsSync(APP_BUNDLE_PATH)) {
        checks.push(check('clawix-app', 'ok', `Clawix.app installed at ${APP_BUNDLE_PATH}`, null));
    } else {
        checks.push(check('clawix-app', 'ok', 'Clawix.app not installed (optional)', null));
    }

    const stateFile = BRIDGE_STATUS_FILE;
    if (!fs.existsSync(stateFile)) {
        checks.push(check('heartbeat', 'warn',
            'bridge-status.json missing.',
            'this build of clawix-bridge predates heartbeat support, or the daemon never started.'));
    } else {
        try {
            const j = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
            const last = Date.parse(j.lastHeartbeatAt || '');
            const age = Number.isFinite(last) ? Date.now() - last : Infinity;
            if (age > 10_000) {
                checks.push(check('heartbeat', 'fail',
                    `last daemon heartbeat ${Math.round(age / 1000)}s ago.`,
                    'restart with `clawix restart` and check `clawix logs`.'));
            } else {
                checks.push(check('heartbeat', 'ok', `heartbeat fresh (${Math.round(age / 1000)}s ago)`, null));
            }
        } catch (e) {
            checks.push(check('heartbeat', 'fail', 'bridge-status.json is not valid JSON.', 'restart with `clawix restart`.'));
        }
    }

    return checks;
}

function print(checks, { json = false } = {}) {
    const summary = checks.reduce((acc, c) => {
        acc[c.level] = (acc[c.level] || 0) + 1;
        return acc;
    }, {});
    if (json) {
        process.stdout.write(JSON.stringify({ checks, summary }, null, 2) + '\n');
        return summary;
    }
    process.stdout.write('\n');
    for (const c of checks) {
        const head = '  ' + ui.bullet(c.level) + '  ' + c.message;
        process.stdout.write(head + '\n');
        if (c.fix) {
            process.stdout.write('     ' + ui.dim('→ ' + c.fix) + '\n');
        }
    }
    process.stdout.write('\n');
    const ok = summary.ok || 0;
    const warn = summary.warn || 0;
    const fail = summary.fail || 0;
    let line = `${ok} ok`;
    if (warn) line += `, ${ui.yellow(warn + ' warn')}`;
    if (fail) line += `, ${ui.red(fail + ' fail')}`;
    process.stdout.write(line + '\n');
    return summary;
}

module.exports = { run, print };
