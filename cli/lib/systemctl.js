'use strict';

// systemctl backend for the Linux build of the npm CLI. Mirrors the
// public surface of `launchctl.js` so `daemon.js`, `up.js`, and
// `service.js` can call into either module without branching.
//
// The unit name `clawix-bridge.service` is shared with the Tauri GUI's
// `service_manager.rs`, the AppImage AppRun, and the .deb postinst, so
// only one daemon ever runs even if the user installed all three.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const {
  LAUNCH_AGENTS_DIR,
  BRIDGE_LABEL,
  MENUBAR_LABEL,
  BRIDGE_PORT
} = require('./platform');

const BRIDGE_UNIT_NAME = 'clawix-bridge.service';
const MENUBAR_UNIT_NAME = 'clawix-menubar.service';

function unitPath(unitName) {
  return path.join(LAUNCH_AGENTS_DIR, unitName);
}

function bridgePlist(binaryPath, suiteName = 'clawix.bridge') {
  // The function name mirrors launchctl.js even though the output is a
  // systemd unit, so call sites stay polymorphic.
  return `[Unit]
Description=Clawix Bridge Daemon
After=network.target

[Service]
ExecStart=${binaryPath}
Environment=CLAWIX_BRIDGE_PORT=${BRIDGE_PORT}
Environment=CLAWIX_BRIDGE_DEFAULTS_SUITE=${suiteName}
StandardOutput=append:/tmp/clawix-bridge.out
StandardError=append:/tmp/clawix-bridge.err
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
`;
}

function menubarPlist(binaryPath) {
  return `[Unit]
Description=Clawix Menubar Helper
After=graphical-session.target

[Service]
ExecStart=${binaryPath}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
`;
}

function writePlist(label, contents) {
  fs.mkdirSync(LAUNCH_AGENTS_DIR, { recursive: true });
  const unitName = label === BRIDGE_LABEL ? BRIDGE_UNIT_NAME : MENUBAR_UNIT_NAME;
  fs.writeFileSync(unitPath(unitName), contents);
}

function plistPath(label) {
  const unitName = label === BRIDGE_LABEL ? BRIDGE_UNIT_NAME : MENUBAR_UNIT_NAME;
  return unitPath(unitName);
}

function userctl(args) {
  return spawnSync('/usr/bin/systemctl', ['--user', ...args], { stdio: 'inherit' }).status;
}

function userctlSilent(args) {
  return spawnSync('/usr/bin/systemctl', ['--user', ...args], { stdio: 'pipe' });
}

function bootstrap(label) {
  const unit = label === BRIDGE_LABEL ? BRIDGE_UNIT_NAME : MENUBAR_UNIT_NAME;
  userctl(['daemon-reload']);
  return userctl(['enable', '--now', unit]);
}

function bootout(label) {
  const unit = label === BRIDGE_LABEL ? BRIDGE_UNIT_NAME : MENUBAR_UNIT_NAME;
  userctl(['disable', '--now', unit]);
  try { fs.unlinkSync(unitPath(unit)); } catch (_) {}
  return userctl(['daemon-reload']);
}

function kickstart(label) {
  const unit = label === BRIDGE_LABEL ? BRIDGE_UNIT_NAME : MENUBAR_UNIT_NAME;
  return userctl(['restart', unit]);
}

function isLoaded(label) {
  const unit = label === BRIDGE_LABEL ? BRIDGE_UNIT_NAME : MENUBAR_UNIT_NAME;
  const result = userctlSilent(['is-active', '--quiet', unit]);
  return result.status === 0;
}

function describe(label) {
  const unit = label === BRIDGE_LABEL ? BRIDGE_UNIT_NAME : MENUBAR_UNIT_NAME;
  const result = userctlSilent(['status', unit]);
  if (result.status !== 0 && result.status !== 3) return null;
  return result.stdout.toString('utf8');
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
  BRIDGE_UNIT_NAME,
  MENUBAR_UNIT_NAME
};
