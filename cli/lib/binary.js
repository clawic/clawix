'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {
  BIN_DIR,
  APP_BUNDLED_DAEMON,
  APP_BUNDLE_PATH,
  DAEMON_BIN_NAME,
  MENUBAR_BIN_NAME,
  IS_WINDOWS
} = require('./platform');

// Read ~/.clawix/bin/manifest.json once. Dev links written by
// scripts-dev/cli-link.sh stamp `source: "npm-link"`, which forces
// the resolver to prefer the locally-built binaries over whatever
// Clawix.app may ship. Outside dev, the manifest is either missing
// or stamped `"source": "github-release"` and the .app's helper wins.
function readManifest() {
  const p = path.join(BIN_DIR, 'manifest.json');
  if (!fs.existsSync(p)) return null;
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}

function isDevLink() {
  const m = readManifest();
  return !!m && m.source === 'npm-link';
}

// Resolve which binary to drive at runtime. Order:
//   1. Explicit override (testing).
//   2. Dev link (manifest.source === 'npm-link') wins so a Clawix.app
//      installed alongside does not silently shadow the workspace build.
//   3. Clawix.app's embedded daemon if installed.
//   4. The npm-installed daemon under ~/.clawix/bin/.
function resolveBridged() {
  const override = process.env.CLAWIX_BRIDGE_PATH;
  if (override && fs.existsSync(override)) return override;
  const npmBin = path.join(BIN_DIR, DAEMON_BIN_NAME);
  if (isDevLink() && fs.existsSync(npmBin)) return npmBin;
  if (fs.existsSync(APP_BUNDLED_DAEMON)) return APP_BUNDLED_DAEMON;
  return npmBin;
}

function resolveMenubar() {
  const override = process.env.CLAWIX_MENUBAR_PATH;
  if (override && fs.existsSync(override)) return override;
  return path.join(BIN_DIR, MENUBAR_BIN_NAME);
}

function isAppInstalled() {
  if (IS_WINDOWS) {
    // On Windows, "the .app" maps to the daemon binary inside %LOCALAPPDATA%\Clawix\.
    return fs.existsSync(APP_BUNDLED_DAEMON);
  }
  return fs.existsSync(APP_BUNDLE_PATH);
}

module.exports = {
  resolveBridged,
  resolveMenubar,
  isAppInstalled
};
