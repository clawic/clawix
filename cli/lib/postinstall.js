'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');
const crypto = require('node:crypto');
const { spawnSync, execFileSync } = require('node:child_process');

const pkg = require('../package.json');

// ──────────────────────────────────────────────────────────────────
// Pre-flight guards. These run BEFORE we touch the filesystem so a
// blocked install never leaves half-written state behind.
// ──────────────────────────────────────────────────────────────────

// Platform: macOS and Linux. Unsupported targets exit 0 (silent)
// so a workspace install that mentions clawix as a peer doesn't break
// for developers on unsupported targets. The CLI's bin/clawix.js
// refuses to run on those platforms with a clear message.
if (!['darwin', 'linux'].includes(process.platform)) {
  console.log(`clawix: skipping native install on ${process.platform} (unsupported).`);
  process.exit(0);
}
if (!['arm64', 'x64'].includes(process.arch)) {
  console.log(`clawix: skipping native install on ${process.arch} (arm64/x64 only).`);
  process.exit(0);
}

// Sudo redirect. `npm install -g` often runs under sudo on systems
// without a user-owned global prefix. If we honored process.env.HOME
// in that case we'd write to /var/root/.clawix/ (mac) or /root/.clawix/
// (linux), and the user could never start the daemon. Detect the
// original user via SUDO_USER and override HOME so os.homedir() reads
// from the real user's account before we require ./platform (which
// captures HOME at module load).
let chownTarget = null;
if (process.geteuid && process.geteuid() === 0 && process.env.SUDO_USER) {
  const sudoUser = process.env.SUDO_USER;
  let realHome;
  if (process.platform === 'darwin') {
    realHome = path.join('/Users', sudoUser);
  } else {
    // Linux: /etc/passwd is authoritative. Fall back to /home/<user> if
    // getent is unavailable (e.g. sandboxed CI runners).
    try {
      const out = execFileSync('/usr/bin/getent', ['passwd', sudoUser], { encoding: 'utf8' });
      realHome = out.split(':')[5] || path.join('/home', sudoUser);
    } catch (e) {
      realHome = path.join('/home', sudoUser);
    }
  }
  if (fs.existsSync(realHome)) {
    process.env.HOME = realHome;
    chownTarget = sudoUser;
    console.log(
      `clawix: detected \`sudo npm install\`. Installing into ${realHome} for user ${sudoUser}.\n` +
      `        Tip: configure npm to use a user-owned prefix to avoid sudo entirely.`
    );
  } else {
    console.error(
      `clawix: SUDO_USER=${sudoUser} but ${realHome} does not exist; refusing to install into root's home.`
    );
    process.exit(1);
  }
}

// macOS minimum version. The Swift binaries were built with a
// deployment target of macOS 14, so anything older crashes at first
// launch with a cryptic dyld error. Surface the requirement here
// instead. Skipped on Linux.
if (process.platform === 'darwin') {
  const macosMajor = (() => {
    try {
      const out = execFileSync('/usr/bin/sw_vers', ['-productVersion'], { encoding: 'utf8' }).trim();
      const major = parseInt(out.split('.')[0], 10);
      return Number.isFinite(major) ? major : null;
    } catch (e) {
      return null;
    }
  })();
  if (macosMajor !== null && macosMajor < 14) {
    console.error(
      `clawix: requires macOS Sonoma 14 or later (detected macOS ${macosMajor}).\n` +
      `        The bundled binaries will not launch on this system. Aborting.`
    );
    process.exit(1);
  }
}

// Module under test depends on os.homedir(); require AFTER the sudo
// redirect mutates process.env.HOME.
const platform = require('./platform');
const manifest = require('./manifest');

// ──────────────────────────────────────────────────────────────────
// Resolve which tarball to use. The release pipeline writes the SHA
// of the canonical tarball into lib/checksums.json before the npm
// publish, and the postinstall pins to that exact bytes-for-bytes
// asset on the matching GitHub release.
// ──────────────────────────────────────────────────────────────────

const BASE_URL = `https://github.com/clawic/clawix/releases/download/v${pkg.version}`;
let ASSET;
if (process.platform === 'darwin') {
  ASSET = 'clawix-cli-darwin-universal.tar.gz';
} else if (process.platform === 'linux') {
  const linuxArch = process.arch === 'arm64' ? 'aarch64' : 'x86_64';
  ASSET = `clawix-cli-linux-${linuxArch}.tar.gz`;
} else {
  process.exit(0);
}
const URL = `${BASE_URL}/${ASSET}`;

const checksumsPath = path.join(__dirname, 'checksums.json');
let checksums = {};
try {
  checksums = JSON.parse(fs.readFileSync(checksumsPath, 'utf8'));
} catch (e) {
  // checksums.json is empty on a source checkout before the release
  // pipeline has populated it; postinstall just no-ops in that case.
}

// Local-tarball override: cli-smoke.sh sets this to validate the
// install pipeline end-to-end without uploading anything to GitHub.
// Skips both the download and the SHA-256 check; codesign --verify
// still gates the binaries that get extracted.
const localTarball = process.env.CLAWIX_LOCAL_TARBALL || null;

const expectedSha = checksums[ASSET];
if (!localTarball && !expectedSha) {
  console.log(
    `clawix: no checksum recorded for ${ASSET} in this build.\n` +
    `        This is expected if you're running from a source checkout without a release pipeline.\n` +
    `        Set CLAWIX_LOCAL_TARBALL=/path/to/${ASSET} for local testing.`
  );
  process.exit(0);
}

function fetch(u) {
  return new Promise((resolve, reject) => {
    const get = (url, redirects = 0) => {
      if (redirects > 5) return reject(new Error('Too many redirects.'));
      https.get(url, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          if (!res.headers.location) return reject(new Error('Redirect without Location header.'));
          return get(res.headers.location, redirects + 1);
        }
        if (res.statusCode !== 200) {
          return reject(new Error(`HTTP ${res.statusCode} fetching ${url}`));
        }
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => resolve(Buffer.concat(chunks)));
        res.on('error', reject);
      }).on('error', reject);
    };
    get(u);
  });
}

async function fetchWithRetry(url) {
  const delays = [2_000, 4_000, 8_000];
  let lastErr;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      return await fetch(url);
    } catch (err) {
      lastErr = err;
      if (attempt === 3) break;
      const delay = delays[attempt - 1];
      console.error(`clawix: network error fetching tarball (try ${attempt}/3): retrying in ${delay / 1000}s…`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw new Error(
    `could not fetch ${url} after 3 attempts: ${(lastErr && lastErr.message) || lastErr}.\n` +
    `check your network and rerun \`npm install -g clawix\`.`
  );
}

function chownToRealUser(filePath) {
  if (!chownTarget) return;
  const group = process.platform === 'linux' ? chownTarget : 'staff';
  spawnSync('chown', ['-R', `${chownTarget}:${group}`, filePath], { stdio: 'ignore' });
}

async function main() {
  // Atomic install: extract to a sibling tmp dir, verify everything,
  // and only swap into place at the very end. A crash mid-install never
  // leaves a half-populated ~/.clawix/bin/ that would make the CLI
  // misbehave the next time the user runs it.
  fs.mkdirSync(platform.CLAWIX_HOME, { recursive: true });
  chownToRealUser(platform.CLAWIX_HOME);
  const stagingDir = platform.BIN_DIR + '.tmp';
  if (fs.existsSync(stagingDir)) fs.rmSync(stagingDir, { recursive: true, force: true });
  fs.mkdirSync(stagingDir, { recursive: true });

  let data;
  let sha;

  if (localTarball) {
    if (!fs.existsSync(localTarball)) {
      throw new Error(`CLAWIX_LOCAL_TARBALL=${localTarball} does not exist.`);
    }
    console.log(`clawix: using local tarball ${localTarball} (CLAWIX_LOCAL_TARBALL set).`);
    data = fs.readFileSync(localTarball);
    sha = crypto.createHash('sha256').update(data).digest('hex');
  } else {
    console.log(`clawix: fetching ${ASSET} v${pkg.version}…`);
    data = await fetchWithRetry(URL);
    sha = crypto.createHash('sha256').update(data).digest('hex');
    if (sha !== expectedSha) {
      throw new Error(
        `Checksum mismatch for ${ASSET}.\n` +
        `  expected: ${expectedSha}\n` +
        `  got:      ${sha}\n` +
        `Aborting; nothing was installed.`
      );
    }
  }

  const archivePath = path.join(os.tmpdir(), `clawix-${pkg.version}-${process.pid}.tar.gz`);
  fs.writeFileSync(archivePath, data);
  try {
    const r = spawnSync('/usr/bin/tar', ['-xzf', archivePath, '-C', stagingDir], {
      stdio: 'inherit'
    });
    if (r.status !== 0) throw new Error('tar extraction failed.');
  } finally {
    try { fs.unlinkSync(archivePath); } catch {}
  }

  for (const name of ['clawix-bridged', 'clawix-menubar']) {
    const p = path.join(stagingDir, name);
    if (!fs.existsSync(p)) continue;
    fs.chmodSync(p, 0o755);
    if (process.platform === 'darwin') {
      const v = spawnSync('/usr/bin/codesign', ['--verify', '--strict', p], { stdio: 'pipe' });
      if (v.status !== 0) {
        fs.rmSync(stagingDir, { recursive: true, force: true });
        throw new Error(`${name} failed codesign verification; aborting install.`);
      }
    }
  }

  // Promote staging into place atomically. If a previous install
  // existed, swap it aside first and remove it after the new one is
  // settled so the window with no binaries is sub-second.
  if (fs.existsSync(platform.BIN_DIR)) {
    const archive = platform.BIN_DIR + '.old';
    fs.rmSync(archive, { recursive: true, force: true });
    fs.renameSync(platform.BIN_DIR, archive);
    try {
      fs.renameSync(stagingDir, platform.BIN_DIR);
    } catch (err) {
      fs.renameSync(archive, platform.BIN_DIR);
      throw err;
    }
    fs.rmSync(archive, { recursive: true, force: true });
  } else {
    fs.renameSync(stagingDir, platform.BIN_DIR);
  }

  manifest.write({
    version: pkg.version,
    bridgeLabel: platform.BRIDGE_LABEL,
    menubarLabel: platform.MENUBAR_LABEL,
    port: platform.BRIDGE_PORT,
    asset: ASSET,
    sha256: sha,
    installedAt: new Date().toISOString(),
    source: localTarball ? 'local' : 'github-release'
  });

  chownToRealUser(platform.CLAWIX_HOME);

  console.log('clawix: installed. Run `clawix up` to start the bridge and pair your phone.');
}

main().catch((err) => {
  console.error('clawix postinstall failed:');
  console.error(err.message || err);
  process.exit(1);
});
