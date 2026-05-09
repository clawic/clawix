'use strict';

const fs = require('node:fs');
const path = require('node:path');
const launchctl = require('./service');
const { BIN_DIR, BRIDGE_LABEL, MENUBAR_LABEL } = require('./platform');

function uninstall({ keepState = true } = {}) {
  // Tear down LaunchAgents the npm side registered. The GUI's own
  // SMAppService registration is independent and is not touched here.
  launchctl.bootout(MENUBAR_LABEL);
  launchctl.bootout(BRIDGE_LABEL);

  for (const label of [BRIDGE_LABEL, MENUBAR_LABEL]) {
    const p = launchctl.plistPath(label);
    if (fs.existsSync(p)) {
      try { fs.unlinkSync(p); } catch {}
    }
  }

  if (fs.existsSync(BIN_DIR)) {
    fs.rmSync(BIN_DIR, { recursive: true, force: true });
  }
  if (!keepState) {
    const stateDir = path.join(BIN_DIR, '..', 'state');
    if (fs.existsSync(stateDir)) {
      fs.rmSync(stateDir, { recursive: true, force: true });
    }
  }
}

module.exports = { uninstall };
