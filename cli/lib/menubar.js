'use strict';

const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const launchctl = require('./service');
const { resolveMenubar } = require('./binary');
const { MENUBAR_LABEL } = require('./platform');

function isClawixAppRunning() {
  // The GUI installs its own MenuBarExtra; running the CLI menubar
  // alongside it shows two near-identical icons. Skip when the .app
  // is up. Match by executable name so this works for both the
  // installed bundle in /Applications and the dev build under
  // ~/Library/Caches/Clawix-Dev (the executable is named `Clawix`
  // in both cases).
  const result = spawnSync('/usr/bin/pgrep', ['-x', 'Clawix'], { stdio: 'pipe' });
  return result.status === 0;
}

function start() {
  const binary = resolveMenubar();
  if (!fs.existsSync(binary)) {
    // Menubar binary is optional: postinstall ships it but a user
    // could have removed it manually. The CLI still works without it.
    return { skipped: true, reason: 'menubar binary not present' };
  }
  if (isClawixAppRunning()) {
    return {
      skipped: true,
      reason: 'Clawix.app is running and shows the bridge controls in its own menu bar item'
    };
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
