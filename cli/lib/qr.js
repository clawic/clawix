'use strict';

// Pairing-QR rendering. Delegated entirely to `qrcode-terminal`, vendored
// under ./vendor/qrcode-terminal/. We vendor it instead of declaring it as
// a dep so the tarball published to npm is fully self-contained.

const qrcodeTerminal = require('./vendor/qrcode-terminal/lib/main');

function generate(text, opts = {}, cb) {
    return qrcodeTerminal.generate(text, opts, cb);
}

module.exports = { generate };
