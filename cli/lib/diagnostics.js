'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');

function tryExec(cmd, args, opts = {}) {
    try {
        return {
            ok: true,
            stdout: execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts }).trim()
        };
    } catch (e) {
        return { ok: false, stdout: '', error: e };
    }
}

function macosVersion() {
    const r = tryExec('/usr/bin/sw_vers', ['-productVersion']);
    if (!r.ok) return null;
    const major = parseInt(r.stdout.split('.')[0], 10);
    return Number.isFinite(major) ? { full: r.stdout, major } : null;
}

function codexInPath() {
    const r = tryExec('/usr/bin/which', ['codex']);
    if (r.ok && r.stdout) return r.stdout;
    const candidates = [
        '/Applications/Codex.app/Contents/Resources/codex',
        '/opt/homebrew/bin/codex',
        '/usr/local/bin/codex',
        '/usr/bin/codex'
    ];
    for (const c of candidates) {
        if (fs.existsSync(c)) return c;
    }
    return null;
}

function lsofPort(port) {
    const r = spawnSync('/usr/sbin/lsof', ['-nP', '-iTCP:' + port, '-sTCP:LISTEN'], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore']
    });
    if (r.status !== 0 || !r.stdout) return [];
    return r.stdout.split('\n').slice(1).filter(Boolean).map((line) => {
        const cols = line.split(/\s+/);
        return { command: cols[0], pid: cols[1], user: cols[2] };
    });
}

function processExePath(pid) {
    const r = tryExec('/bin/ps', ['-p', String(pid), '-o', 'comm=']);
    return r.ok ? r.stdout : null;
}

function lanIpv4() {
    const ifs = os.networkInterfaces();
    for (const name of ['en0', 'en1']) {
        const list = ifs[name];
        if (!list) continue;
        for (const e of list) {
            if (e.family === 'IPv4' && !e.internal && !e.address.startsWith('169.254.')) {
                return { iface: name, address: e.address };
            }
        }
    }
    return null;
}

function tailscaleIpv4() {
    const ifs = os.networkInterfaces();
    for (const [name, list] of Object.entries(ifs)) {
        if (!name.startsWith('utun')) continue;
        for (const e of list) {
            if (e.family !== 'IPv4') continue;
            const parts = e.address.split('.').map((p) => parseInt(p, 10));
            if (parts.length === 4 && parts[0] === 100 && parts[1] >= 64 && parts[1] <= 127) {
                return { iface: name, address: e.address };
            }
        }
    }
    return null;
}

function verifyCodesign(file) {
    if (!fs.existsSync(file)) return { exists: false };
    const r = spawnSync('/usr/bin/codesign', ['--verify', '--strict', file], { stdio: ['ignore', 'pipe', 'pipe'] });
    return { exists: true, valid: r.status === 0, stderr: r.stderr ? r.stderr.toString() : '' };
}

function plutilLint(plistPath) {
    if (!fs.existsSync(plistPath)) return { exists: false };
    const r = spawnSync('/usr/bin/plutil', ['-lint', plistPath], { stdio: ['ignore', 'pipe', 'pipe'] });
    return { exists: true, valid: r.status === 0 };
}

function launchctlPrint(label) {
    const uid = process.getuid();
    const r = spawnSync('/bin/launchctl', ['print', `gui/${uid}/${label}`], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe']
    });
    if (r.status !== 0) return { loaded: false };
    const stdout = r.stdout || '';
    const state = (stdout.match(/state\s*=\s*(\S+)/) || [])[1] || 'unknown';
    const lastExit = parseInt((stdout.match(/last exit code\s*=\s*(-?\d+)/) || [])[1] || 'NaN', 10);
    const programMatch = stdout.match(/program\s*=\s*(\S+)/);
    return {
        loaded: true,
        state,
        lastExitCode: Number.isFinite(lastExit) ? lastExit : null,
        program: programMatch ? programMatch[1] : null
    };
}

function firewallBlocked(binaryPath) {
    if (!fs.existsSync(binaryPath)) return { applicable: false };
    const r = tryExec('/usr/libexec/ApplicationFirewall/socketfilterfw', ['--getappblocked', binaryPath]);
    if (!r.ok) return { applicable: true, blocked: null, message: 'socketfilterfw unavailable' };
    const blocked = /is blocked/i.test(r.stdout);
    return { applicable: true, blocked, message: r.stdout };
}

function plistBuddyRead(plistFile, key) {
    if (!fs.existsSync(plistFile)) return null;
    const r = tryExec('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, plistFile]);
    return r.ok ? (r.stdout || null) : null;
}

module.exports = {
    macosVersion,
    codexInPath,
    lsofPort,
    processExePath,
    lanIpv4,
    tailscaleIpv4,
    verifyCodesign,
    plutilLint,
    launchctlPrint,
    firewallBlocked,
    plistBuddyRead
};
