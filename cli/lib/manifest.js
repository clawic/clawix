'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { BIN_DIR } = require('./platform');

const MANIFEST_PATH = path.join(BIN_DIR, 'manifest.json');

function read() {
  try {
    const raw = fs.readFileSync(MANIFEST_PATH, 'utf8');
    return JSON.parse(raw);
  } catch (e) {
    return null;
  }
}

function write(manifest) {
  fs.mkdirSync(BIN_DIR, { recursive: true });
  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n');
}

module.exports = { read, write, MANIFEST_PATH };
