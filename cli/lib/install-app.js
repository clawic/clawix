'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync, execFileSync } = require('node:child_process');
const https = require('node:https');

const DMG_URL = 'https://github.com/clawic/clawix/releases/latest/download/Clawix.dmg';
const APP_DEST = '/Applications/Clawix.app';

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    const get = (u) => {
      https.get(u, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          file.close();
          fs.unlinkSync(dest);
          const next = res.headers.location;
          if (!next) return reject(new Error('redirect without location'));
          return get(next);
        }
        if (res.statusCode !== 200) {
          file.close();
          fs.unlinkSync(dest);
          return reject(new Error(`HTTP ${res.statusCode} fetching ${u}`));
        }
        const total = Number(res.headers['content-length'] || 0);
        let received = 0;
        let lastPrint = 0;
        res.on('data', (chunk) => {
          received += chunk.length;
          const now = Date.now();
          if (total > 0 && now - lastPrint > 200) {
            const pct = ((received / total) * 100).toFixed(1);
            process.stdout.write(`\r  downloading: ${pct}%   `);
            lastPrint = now;
          }
        });
        res.pipe(file);
        file.on('finish', () => {
          file.close(() => {
            process.stdout.write('\r  downloading: done       \n');
            resolve();
          });
        });
      }).on('error', (e) => {
        file.close();
        try { fs.unlinkSync(dest); } catch {}
        reject(e);
      });
    };
    get(url);
  });
}

async function install() {
  if (fs.existsSync(APP_DEST)) {
    console.log(`${APP_DEST} already exists. Quit Clawix.app first to replace it.`);
    return;
  }
  const cacheDir = path.join(os.homedir(), 'Library', 'Caches', 'clawix');
  fs.mkdirSync(cacheDir, { recursive: true });
  const dmgPath = path.join(cacheDir, 'Clawix.dmg');

  console.log('Fetching Clawix.dmg…');
  await download(DMG_URL, dmgPath);

  console.log('Verifying signature…');
  const verify = spawnSync('codesign', ['--verify', '--deep', '--strict', dmgPath], {
    stdio: 'inherit'
  });
  if (verify.status !== 0) {
    throw new Error('Downloaded DMG failed codesign verification.');
  }

  console.log('Mounting…');
  const attach = spawnSync('hdiutil', ['attach', '-nobrowse', '-noverify', dmgPath], {
    encoding: 'utf8'
  });
  if (attach.status !== 0) {
    throw new Error('hdiutil attach failed');
  }
  const mountLine = attach.stdout.split('\n').reverse().find((l) => l.includes('/Volumes/'));
  const mountPoint = mountLine ? mountLine.trim().split('\t').pop() : null;
  if (!mountPoint) {
    throw new Error('Could not determine mount point.');
  }

  try {
    const src = path.join(mountPoint, 'Clawix.app');
    if (!fs.existsSync(src)) {
      throw new Error(`Clawix.app not found inside DMG at ${src}`);
    }
    console.log(`Copying to ${APP_DEST}…`);
    const copy = spawnSync('/usr/bin/ditto', [src, APP_DEST], { stdio: 'inherit' });
    if (copy.status !== 0) {
      throw new Error('ditto failed copying Clawix.app to /Applications');
    }
    spawnSync('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', APP_DEST], { stdio: 'ignore' });
  } finally {
    spawnSync('hdiutil', ['detach', mountPoint, '-quiet'], { stdio: 'ignore' });
  }

  console.log('Opening Clawix.app…');
  spawnSync('/usr/bin/open', [APP_DEST], { stdio: 'inherit' });
  console.log('Done. The GUI is now in /Applications and will manage the bridge from now on.');
}

module.exports = { install };
