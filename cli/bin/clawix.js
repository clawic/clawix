#!/usr/bin/env node
'use strict';

const platform = require('../lib/platform');
const pkg = require('../package.json');

const COMMANDS = ['up', 'start', 'stop', 'status', 'pair', 'unpair', 'logs', 'doctor', 'install-app', 'restart', 'uninstall', 'mesh'];

// Honour --no-color BEFORE require()ing ui.js: ui.js samples
// process.stdout.isTTY + NO_COLOR at module load.
if (process.argv.includes('--no-color')) {
    process.env.NO_COLOR = '1';
}

const ui = require('../lib/ui');

function help() {
    process.stdout.write(`
${ui.bold('clawix')} v${pkg.version} — bridge codex from your phone via your mac.

${ui.bold('usage')}
  clawix <command> [flags]

${ui.bold('commands')}
  up               start bridge + menu bar, show pairing QR, watch live status
  start            start bridge as launchd agent (no QR, no watch)
  stop             stop bridge + menu bar
  restart          restart the bridge
  status           bridge state, port, peers, app presence
  pair             show pairing QR + short code
  unpair           rotate bearer + short code (kicks every paired device)
  mesh             manage paired Macs, workspaces, and remote jobs
  doctor           run health checks across the whole environment
  logs [-f]        tail bridge logs
  install-app      install /Applications/Clawix.app from the latest release
  uninstall        remove ~/.clawix/bin and unregister launchd agents

${ui.bold('flags')}
  --json           machine-readable output (status, pair, doctor)
  --no-color       disable ANSI colors (also honoured: NO_COLOR=1)
  --version, -v    print cli version
  --help, -h       this message

${ui.bold('examples')}
  clawix up                         first-time pairing with live watch
  clawix doctor --json              ci-friendly health check
  clawix logs -f                    debug a bridge that won't connect

${ui.bold('paths')}
  ~/.clawix/bin/                              ${ui.dim('binaries fetched by postinstall')}
  ~/.clawix/state/bridge-status.json          ${ui.dim('daemon heartbeat')}
  ~/Library/LaunchAgents/clawix.bridge.plist  ${ui.dim('launchd registration')}
  ~/Library/Preferences/clawix.bridge.plist   ${ui.dim('pairing bearer + short code')}
  /tmp/clawix-bridged.{out,err}               ${ui.dim('daemon logs')}
`);
}

async function main(argv) {
    const args = argv.slice(2).filter((a) => a !== '--no-color');
    if (args.length === 0 || args[0] === '--help' || args[0] === '-h' || args[0] === 'help') {
        help();
        return;
    }
    if (args[0] === '--version' || args[0] === '-v') {
        console.log(pkg.version);
        return;
    }

    platform.ensureSupported();

    const cmd = args[0];
    if (!COMMANDS.includes(cmd)) {
        ui.fail(
            `unknown command "${cmd}".`,
            null,
            'run `clawix --help` to list commands.'
        );
        process.exit(2);
    }
    const rest = args.slice(1);
    const flag = (name) => rest.includes(name);

    switch (cmd) {
        case 'up': {
            const up = require('../lib/up');
            await up.run({ noWatch: flag('--no-watch') });
            return;
        }
        case 'start': {
            const daemon = require('../lib/daemon');
            const r = daemon.start();
            console.log(r.reused ? 'bridge: already running' : `bridge: started (${r.binary})`);
            return;
        }
        case 'stop': {
            const daemon = require('../lib/daemon');
            const menubar = require('../lib/menubar');
            menubar.stop();
            daemon.stop();
            console.log('bridge: stopped');
            return;
        }
        case 'restart': {
            const daemon = require('../lib/daemon');
            daemon.restart();
            console.log('bridge: restarted');
            return;
        }
        case 'status': {
            const daemon = require('../lib/daemon');
            const menubar = require('../lib/menubar');
            const s = await daemon.status();
            const m = menubar.isRunning();
            const view = {
                bridge: {
                    loaded: s.loaded,
                    reachable: s.reachable,
                    port: s.port,
                    peerCount: s.peerCount,
                    heartbeatAgeMs: s.heartbeatAgeMs,
                    heartbeatStale: s.heartbeatStale
                },
                binary: s.binary,
                menubar: m,
                app: { installed: s.appInstalled, path: '/Applications/Clawix.app' }
            };
            if (flag('--json')) {
                console.log(JSON.stringify(view, null, 2));
            } else {
                let bridgeState;
                if (!s.loaded) bridgeState = 'not running';
                else if (!s.reachable) bridgeState = 'loaded but not reachable';
                else if (s.heartbeatStale) bridgeState = 'reachable, heartbeat stale';
                else bridgeState = 'running';
                console.log(`bridge   : ${bridgeState} (port ${s.port})`);
                if (s.peerCount !== null && s.peerCount !== undefined) {
                    console.log(`peers    : ${s.peerCount}`);
                }
                if (s.heartbeatAgeMs !== null && s.heartbeatAgeMs !== undefined) {
                    console.log(`heartbeat: ${Math.round(s.heartbeatAgeMs / 1000)}s ago`);
                }
                console.log(`binary   : ${s.binary}`);
                console.log(`menubar  : ${m ? 'running' : 'not running'}`);
                console.log(`Clawix.app: ${s.appInstalled ? 'installed' : 'not installed'}`);
            }
            return;
        }
        case 'pair': {
            const pair = require('../lib/pair');
            pair.show({ json: flag('--json') });
            return;
        }
        case 'unpair': {
            const { unpair } = require('../lib/unpair');
            unpair();
            return;
        }
        case 'logs': {
            const logs = require('../lib/logs');
            logs.tail({ follow: flag('-f') || flag('--follow') });
            return;
        }
        case 'mesh': {
            const mesh = require('../lib/mesh');
            await mesh.run(rest.filter((a) => a !== '--json'), { json: flag('--json') });
            return;
        }
        case 'doctor': {
            const doctor = require('../lib/doctor');
            const checks = doctor.run();
            const summary = doctor.print(checks, { json: flag('--json') });
            if (summary.fail) process.exit(1);
            return;
        }
        case 'install-app': {
            const installApp = require('../lib/install-app');
            await installApp.install();
            return;
        }
        case 'uninstall': {
            const { uninstall } = require('../lib/uninstall');
            uninstall({ keepState: !flag('--purge') });
            console.log('clawix: uninstalled. To remove the npm package run `npm uninstall -g clawix`.');
            return;
        }
    }
}

main(process.argv).catch((err) => {
    ui.fail(
        (err && err.message) || String(err),
        null,
        'if this looks wrong, run `clawix doctor` to diagnose the environment.'
    );
    process.exit(1);
});
