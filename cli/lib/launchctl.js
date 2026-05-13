'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const {
  LAUNCH_AGENTS_DIR,
  BRIDGE_LABEL,
  MENUBAR_LABEL,
  BRIDGE_PORT
} = require('./platform');

function userDomain() {
  return `gui/${process.getuid()}`;
}

function plistPath(label) {
  return path.join(LAUNCH_AGENTS_DIR, `${label}.plist`);
}

function bridgePlist(binaryPath, suiteName = 'clawix.bridge') {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>                       <string>${BRIDGE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${binaryPath}</string>
    </array>
    <key>RunAtLoad</key>                   <true/>
    <key>KeepAlive</key>                   <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLAWIX_BRIDGE_PORT</key>     <string>${BRIDGE_PORT}</string>
        <key>CLAWIX_BRIDGE_DEFAULTS_SUITE</key> <string>${suiteName}</string>
    </dict>
    <key>StandardOutPath</key>             <string>/tmp/clawix-bridge.out</string>
    <key>StandardErrorPath</key>           <string>/tmp/clawix-bridge.err</string>
</dict>
</plist>
`;
}

function menubarPlist(binaryPath) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>                       <string>${MENUBAR_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${binaryPath}</string>
    </array>
    <key>RunAtLoad</key>                   <true/>
    <key>KeepAlive</key>                   <true/>
    <key>StandardOutPath</key>             <string>/tmp/clawix-menubar.out</string>
    <key>StandardErrorPath</key>           <string>/tmp/clawix-menubar.err</string>
</dict>
</plist>
`;
}

function writePlist(label, contents) {
  fs.mkdirSync(LAUNCH_AGENTS_DIR, { recursive: true });
  fs.writeFileSync(plistPath(label), contents);
}

function bootstrap(label) {
  return spawnSync('/bin/launchctl', ['bootstrap', userDomain(), plistPath(label)], {
    stdio: 'inherit'
  }).status;
}

function bootout(label) {
  return spawnSync('/bin/launchctl', ['bootout', `${userDomain()}/${label}`], {
    stdio: 'ignore'
  }).status;
}

function kickstart(label) {
  return spawnSync('/bin/launchctl', ['kickstart', '-k', `${userDomain()}/${label}`], {
    stdio: 'inherit'
  }).status;
}

function isLoaded(label) {
  const result = spawnSync('/bin/launchctl', ['print', `${userDomain()}/${label}`], {
    stdio: 'pipe'
  });
  return result.status === 0;
}

function describe(label) {
  const result = spawnSync('/bin/launchctl', ['print', `${userDomain()}/${label}`], {
    stdio: 'pipe'
  });
  if (result.status !== 0) return null;
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
  MENUBAR_LABEL
};
