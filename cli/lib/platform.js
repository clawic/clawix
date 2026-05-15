'use strict';

// @persistent-surface-wrapper
const os = require('node:os');
const path = require('node:path');

const SUPPORTED_PLATFORMS = new Set(['darwin', 'win32', 'linux']);
const SUPPORTED_ARCHES = new Set(['arm64', 'x64']);

function isSupported() {
  return SUPPORTED_PLATFORMS.has(process.platform) && SUPPORTED_ARCHES.has(process.arch);
}

function ensureSupported() {
  if (isSupported()) return;
  const msg = [
    `clawix v${require('../package.json').version} supports macOS, Linux, and Windows (arm64 or x64) today.`,
    `Detected: ${process.platform} ${process.arch}.`
  ].join('\n');
  console.error(msg);
  process.exit(1);
}

const IS_WINDOWS = process.platform === 'win32';
const IS_LINUX = process.platform === 'linux';
const IS_MAC = process.platform === 'darwin';

const HOME = os.homedir();
const CLAWIX_HOME = path.join(HOME, '.clawix');
const BIN_DIR = path.join(CLAWIX_HOME, 'bin');
const STATE_DIR = path.join(CLAWIX_HOME, 'state');
const BRIDGE_STATUS_FILE = path.join(STATE_DIR, 'bridge-status.json');
const Env = Object.freeze({
  clawixBridgePath: 'CLAWIX_BRIDGE_PATH',
  clawixMenubarPath: 'CLAWIX_MENUBAR_PATH',
  clawixLocalTarball: 'CLAWIX_LOCAL_TARBALL',
  localAppData: 'LOCALAPPDATA',
  xdgConfigHome: 'XDG_CONFIG_HOME',
});

// Per-platform location of the autostart manifest. macOS uses launchd
// LaunchAgents (XML plist); Linux uses systemd user units; Windows uses
// a registry-shaped autostart folder under LOCALAPPDATA. The
// ServiceManager abstraction picks the backend at runtime by sniffing
// process.platform.
let LAUNCH_AGENTS_DIR;
if (IS_WINDOWS) {
  LAUNCH_AGENTS_DIR = path.join(process.env[Env.localAppData] || HOME, 'Clawix', 'autostart');
} else if (IS_LINUX) {
  const xdgConfig = process.env[Env.xdgConfigHome] || path.join(HOME, '.config');
  LAUNCH_AGENTS_DIR = path.join(xdgConfig, 'systemd', 'user');
} else {
  LAUNCH_AGENTS_DIR = path.join(HOME, 'Library', 'LaunchAgents');
}

// Keep these three constants in sync with their Swift mirrors in
// `macos/Sources/Clawix/Bridge/BridgeAgentControl.swift` (and with
// `windows/Clawix.App/Services/AutoStartService.cs`). The GUI talks to
// the same labels and loopback port, so a drift silently splits the
// bridge in two on a machine that has both installed.
const BRIDGE_LABEL = 'clawix.bridge';
const MENUBAR_LABEL = 'clawix.menubar';
const BRIDGE_PORT = 24080;
const BRIDGE_HTTP_PORT = 24081;

let APP_BUNDLE_PATH;
let APP_BUNDLED_DAEMON;
if (IS_WINDOWS) {
  APP_BUNDLE_PATH = path.join(process.env[Env.localAppData] || HOME, 'Clawix');
  APP_BUNDLED_DAEMON = path.join(APP_BUNDLE_PATH, 'clawix-bridge.exe');
} else if (IS_LINUX) {
  // Resolved at runtime by service_manager.rs / daemon.js because the
  // installer might be the .deb (/opt/clawix), the AppImage AppDir
  // (extracted), or the npm tarball (~/.clawix/bin). We expose the most
  // common static path here as a hint; real lookup walks all three.
  APP_BUNDLE_PATH = '/opt/clawix';
  APP_BUNDLED_DAEMON = '/opt/clawix/clawix-bridge';
} else {
  APP_BUNDLE_PATH = '/Applications/Clawix.app';
  APP_BUNDLED_DAEMON = path.join(APP_BUNDLE_PATH, 'Contents', 'Helpers', 'clawix-bridge');
}

const DAEMON_BIN_NAME = IS_WINDOWS ? 'clawix-bridge.exe' : 'clawix-bridge';
const MENUBAR_BIN_NAME = IS_WINDOWS ? 'clawix-menubar.exe' : 'clawix-menubar';

module.exports = {
  isSupported,
  ensureSupported,
  IS_WINDOWS,
  IS_LINUX,
  IS_MAC,
  CLAWIX_HOME,
  BIN_DIR,
  STATE_DIR,
  BRIDGE_STATUS_FILE,
  Env,
  LAUNCH_AGENTS_DIR,
  BRIDGE_LABEL,
  MENUBAR_LABEL,
  BRIDGE_PORT,
  BRIDGE_HTTP_PORT,
  APP_BUNDLE_PATH,
  APP_BUNDLED_DAEMON,
  DAEMON_BIN_NAME,
  MENUBAR_BIN_NAME
};
