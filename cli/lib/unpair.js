'use strict';

const { spawnSync } = require('node:child_process');
const ui = require('./ui');
const daemon = require('./daemon');
const { BRIDGE_LABEL } = require('./platform');

const SUITE = 'clawix.bridge';
const KEYS = ['ClawixBridge.Bearer.v1', 'ClawixBridge.ShortCode.v1'];

// Wipe the pairing bearer + short code from the shared UserDefaults
// suite, then bounce the daemon. The daemon's eager-trigger at startup
// generates a fresh bearer + fresh short code, so any iPhone (or other
// device) holding the previous pair can no longer authenticate.
//
// We use the `defaults` command instead of PlistBuddy so cfprefsd
// notices the change and forwards it to running processes that have
// the same suite open. This avoids a race where the daemon would still
// honour the old in-memory bearer until restart.
function unpair() {
    const wasLoaded = daemon.status ? false : true; // unused; kept for future
    const initiallyLoaded = isLaunchAgentLoaded();

    if (initiallyLoaded) {
        daemon.stop();
    }

    for (const key of KEYS) {
        spawnSync('/usr/bin/defaults', ['delete', SUITE, key], { stdio: 'ignore' });
    }
    // Force cfprefsd to flush the suite, otherwise the daemon may read
    // stale values from its cache when it restarts on the same boot.
    spawnSync('/usr/bin/defaults', ['read', SUITE], { stdio: 'ignore' });

    if (initiallyLoaded) {
        try {
            daemon.start();
        } catch (e) {
            ui.fail(
                'unpair removed the credentials but failed to restart the bridge.',
                (e && e.message) || 'launchctl bootstrap exited with an error.',
                'run `clawix start` manually to bring it back.'
            );
            process.exit(1);
        }
    }

    process.stdout.write('clawix: unpaired. all previously paired devices must scan a fresh QR.\n');
}

function isLaunchAgentLoaded() {
    const r = spawnSync('/bin/launchctl', ['print', `gui/${process.getuid()}/${BRIDGE_LABEL}`], { stdio: 'ignore' });
    return r.status === 0;
}

module.exports = { unpair };
