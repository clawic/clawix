'use strict';

const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const os = require('node:os');
const launchctl = require('./service');
const { resolveBridged, isAppInstalled } = require('./binary');
const { BRIDGE_LABEL, BRIDGE_PORT } = require('./platform');

const STATE_FILE = path.join(os.homedir(), '.clawix', 'state', 'bridge-status.json');

function readHeartbeat() {
    try {
        return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    } catch (e) {
        return null;
    }
}

async function probePort(port = BRIDGE_PORT, timeoutMs = 500) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    const done = (up) => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(up);
    };
    socket.once('connect', () => done(true));
    socket.once('error', () => done(false));
    socket.setTimeout(timeoutMs, () => done(false));
  });
}

function start() {
  const binary = resolveBridged();
  if (!fs.existsSync(binary)) {
    throw new Error(
      `clawix-bridged not found at ${binary}.\n` +
      `Run \`clawix uninstall\` followed by \`npm install -g clawix\` to repair.`
    );
  }
  if (launchctl.isLoaded(BRIDGE_LABEL)) {
    // Already running; nothing to do. The plist may have been written
    // by a previous `clawix start` or by Clawix.app: either way the
    // daemon is up and serving the same loopback port.
    return { reused: true, binary };
  }
  launchctl.writePlist(BRIDGE_LABEL, launchctl.bridgePlist(binary));
  const code = launchctl.bootstrap(BRIDGE_LABEL);
  if (code !== 0) {
    throw new Error(`launchctl bootstrap exited ${code}`);
  }
  return { reused: false, binary };
}

function stop() {
  launchctl.bootout(BRIDGE_LABEL);
}

function restart() {
  if (launchctl.isLoaded(BRIDGE_LABEL)) {
    launchctl.kickstart(BRIDGE_LABEL);
  } else {
    return start();
  }
  return { kicked: true };
}

async function status() {
  const loaded = launchctl.isLoaded(BRIDGE_LABEL);
  const reachable = await probePort();
  const heartbeat = readHeartbeat();
  let heartbeatAgeMs = null;
  if (heartbeat && heartbeat.lastHeartbeatAt) {
    const t = Date.parse(heartbeat.lastHeartbeatAt);
    if (Number.isFinite(t)) heartbeatAgeMs = Date.now() - t;
  }
  return {
    loaded,
    reachable,
    port: BRIDGE_PORT,
    binary: resolveBridged(),
    appInstalled: isAppInstalled(),
    peerCount: heartbeat ? (heartbeat.peerCount || 0) : null,
    heartbeatAgeMs,
    heartbeatStale: heartbeatAgeMs !== null && heartbeatAgeMs > 10_000
  };
}

module.exports = { start, stop, restart, status, probePort, readHeartbeat };
