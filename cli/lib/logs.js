'use strict';

const fs = require('node:fs');
const { spawn } = require('node:child_process');

const OUT = '/tmp/clawix-bridge.out';
const ERR = '/tmp/clawix-bridge.err';

function tail({ follow = false } = {}) {
  const present = [OUT, ERR].filter((p) => fs.existsSync(p));
  if (present.length === 0) {
    console.error('No bridge logs yet. Start the bridge with `clawix start`.');
    return;
  }
  const args = follow ? ['-F', '-n', '200', ...present] : ['-n', '200', ...present];
  const child = spawn('/usr/bin/tail', args, { stdio: 'inherit' });
  process.on('SIGINT', () => child.kill('SIGINT'));
}

module.exports = { tail };
