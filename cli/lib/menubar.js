'use strict';

const fs = require('node:fs');
const launchctl = require('./launchctl');
const { resolveMenubar } = require('./binary');
const { MENUBAR_LABEL } = require('./platform');

function start() {
  const binary = resolveMenubar();
  if (!fs.existsSync(binary)) {
    // Menubar binary is optional: postinstall ships it but a user
    // could have removed it manually. The CLI still works without it.
    return { skipped: true, reason: 'menubar binary not present' };
  }
  if (launchctl.isLoaded(MENUBAR_LABEL)) {
    return { reused: true };
  }
  launchctl.writePlist(MENUBAR_LABEL, launchctl.menubarPlist(binary));
  const code = launchctl.bootstrap(MENUBAR_LABEL);
  if (code !== 0) {
    return { skipped: true, reason: `launchctl bootstrap exited ${code}` };
  }
  return { started: true };
}

function stop() {
  launchctl.bootout(MENUBAR_LABEL);
}

function isRunning() {
  return launchctl.isLoaded(MENUBAR_LABEL);
}

module.exports = { start, stop, isRunning };
