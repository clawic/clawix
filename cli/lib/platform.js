'use strict';

const os = require('node:os');
const path = require('node:path');

const SUPPORTED_PLATFORMS = new Set(['darwin']);
const SUPPORTED_ARCHES = new Set(['arm64', 'x64']);

function isSupported() {
  return SUPPORTED_PLATFORMS.has(process.platform) && SUPPORTED_ARCHES.has(process.arch);
}

function ensureSupported() {
  if (isSupported()) return;
  const msg = [
    `clawix v${require('../package.json').version} only supports macOS (arm64 or x64) today.`,
    `Detected: ${process.platform} ${process.arch}.`,
    'Linux and Windows builds are planned; track progress in the repo.'
  ].join('\n');
  console.error(msg);
  process.exit(1);
}

const HOME = os.homedir();
const CLAWIX_HOME = path.join(HOME, '.clawix');
const BIN_DIR = path.join(CLAWIX_HOME, 'bin');
const STATE_DIR = path.join(CLAWIX_HOME, 'state');
const LAUNCH_AGENTS_DIR = path.join(HOME, 'Library', 'LaunchAgents');
const BRIDGE_LABEL = 'clawix.bridge';
const MENUBAR_LABEL = 'clawix.menubar';
const BRIDGE_PORT = 7778;
const APP_BUNDLE_PATH = '/Applications/Clawix.app';
const APP_BUNDLED_DAEMON = path.join(APP_BUNDLE_PATH, 'Contents', 'Helpers', 'clawix-bridged');

module.exports = {
  isSupported,
  ensureSupported,
  CLAWIX_HOME,
  BIN_DIR,
  STATE_DIR,
  LAUNCH_AGENTS_DIR,
  BRIDGE_LABEL,
  MENUBAR_LABEL,
  BRIDGE_PORT,
  APP_BUNDLE_PATH,
  APP_BUNDLED_DAEMON
};
