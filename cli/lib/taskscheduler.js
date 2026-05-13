'use strict';

// Windows backend for the service-manager facade. The Mac plist API is
// adapted to: a JSON config in the autostart folder, a registry "Run"
// entry for auto-start, and direct child_process.spawn for start/stop.
// We do NOT use Windows Service (sc.exe create) because that requires
// admin elevation; the GUI lives in user-space.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync, spawn } = require('node:child_process');

const {
  LAUNCH_AGENTS_DIR,
  BRIDGE_LABEL,
  MENUBAR_LABEL,
  BRIDGE_PORT,
  STATE_DIR
} = require('./platform');

const RUN_KEY = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run';

function plistPath(label) {
  // Compatibility shim: callers think in plist paths; we hand them a
  // JSON manifest with the same lifecycle but the right extension.
  return path.join(LAUNCH_AGENTS_DIR, `${label}.json`);
}

function bridgePlist(binaryPath, suiteName = 'clawix.bridge') {
  return JSON.stringify({
    label: BRIDGE_LABEL,
    program: binaryPath,
    args: [],
    env: {
      CLAWIX_BRIDGE_PORT: String(BRIDGE_PORT),
      CLAWIX_BRIDGE_DEFAULTS_SUITE: suiteName,
    },
    keepAlive: true,
    runAtLoad: true,
    stdoutPath: path.join(STATE_DIR, 'clawix-bridge.out'),
    stderrPath: path.join(STATE_DIR, 'clawix-bridge.err'),
  }, null, 2);
}

function menubarPlist(binaryPath) {
  return JSON.stringify({
    label: MENUBAR_LABEL,
    program: binaryPath,
    args: [],
    keepAlive: true,
    runAtLoad: true,
  }, null, 2);
}

function writePlist(label, contents) {
  fs.mkdirSync(LAUNCH_AGENTS_DIR, { recursive: true });
  fs.writeFileSync(plistPath(label), contents);
  // Register the executable in the Run registry key for auto-start
  // at login (per-user, no admin).
  try {
    const cfg = JSON.parse(contents);
    const program = cfg.program || '';
    if (program) {
      spawnSync('reg', ['add', RUN_KEY, '/v', label, '/t', 'REG_SZ',
                        '/d', `"${program}"`, '/f'], { stdio: 'ignore' });
    }
  } catch { /* tolerate */ }
}

function _readManifest(label) {
  try { return JSON.parse(fs.readFileSync(plistPath(label), 'utf8')); }
  catch { return null; }
}

function _pidFile(label) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  return path.join(STATE_DIR, `${label}.pid`);
}

function bootstrap(label) {
  const cfg = _readManifest(label);
  if (!cfg || !cfg.program) return 1;
  const out = cfg.stdoutPath ? fs.openSync(cfg.stdoutPath, 'a') : 'ignore';
  const err = cfg.stderrPath ? fs.openSync(cfg.stderrPath, 'a') : 'ignore';
  const child = spawn(cfg.program, cfg.args || [], {
    detached: true,
    stdio: ['ignore', out, err],
    env: { ...process.env, ...(cfg.env || {}) },
    windowsHide: true,
  });
  if (typeof child.pid !== 'number') return 1;
  fs.writeFileSync(_pidFile(label), String(child.pid));
  child.unref();
  return 0;
}

function bootout(label) {
  // Stop the running daemon and remove its registry auto-start entry.
  let pid = null;
  try { pid = parseInt(fs.readFileSync(_pidFile(label), 'utf8').trim(), 10); } catch {}
  if (Number.isFinite(pid)) {
    try { process.kill(pid, 'SIGTERM'); } catch {}
    // Force kill after 2s if still alive.
    try {
      spawnSync('taskkill', ['/PID', String(pid), '/F'], { stdio: 'ignore' });
    } catch {}
  }
  try { fs.unlinkSync(_pidFile(label)); } catch {}
  spawnSync('reg', ['delete', RUN_KEY, '/v', label, '/f'], { stdio: 'ignore' });
  return 0;
}

function kickstart(label) {
  bootout(label);
  return bootstrap(label);
}

function isLoaded(label) {
  let pid = null;
  try { pid = parseInt(fs.readFileSync(_pidFile(label), 'utf8').trim(), 10); } catch {}
  if (!Number.isFinite(pid)) return false;
  try { process.kill(pid, 0); return true; } catch { return false; }
}

function describe(label) {
  const cfg = _readManifest(label);
  if (!cfg) return null;
  let pid = null;
  try { pid = parseInt(fs.readFileSync(_pidFile(label), 'utf8').trim(), 10); } catch {}
  return JSON.stringify({ ...cfg, pid, alive: isLoaded(label) }, null, 2);
}

module.exports = {
  plistPath,
  bridgePlist,
  menubarPlist,
  writePlist,
  bootstrap,
  bootout,
  kickstart,
  isLoaded,
  describe,
  BRIDGE_LABEL,
  MENUBAR_LABEL,
};
