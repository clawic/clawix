'use strict';

// Pairing-QR helpers. Encoding and terminal rendering are delegated to
// `qrcode-terminal` (vendored under ./vendor/qrcode-terminal/). We vendor
// it instead of declaring it as a dep so the tarball published to npm is
// fully self-contained: nothing else has to resolve at install time and
// the postinstall script can't ever fail to find it.
//
// On top of that we provide a tiny PNG renderer (built-in zlib only) so
// the user can `open` a guaranteed-scan image when the in-terminal QR
// is too cramped or the font has line-height seams.

const zlib = require('node:zlib');
const qrcodeTerminal = require('./vendor/qrcode-terminal/lib/main');
const QRCode = require('./vendor/qrcode-terminal/vendor/QRCode');
const QRErrorCorrectLevel = require('./vendor/qrcode-terminal/vendor/QRCode/QRErrorCorrectLevel');

// Render the QR to stdout (or via callback) using qrcode-terminal.
function generate(text, opts = {}, cb) {
    return qrcodeTerminal.generate(text, opts, cb);
}

// Build the bool matrix using the same encoder qrcode-terminal uses
// internally. Auto-picks the smallest version (typeNumber=-1).
function buildMatrix(text, errorLevel = QRErrorCorrectLevel.M) {
    const code = new QRCode(-1, errorLevel);
    code.addData(text);
    code.make();
    const size = code.getModuleCount();
    const matrix = [];
    for (let r = 0; r < size; r++) {
        const row = [];
        for (let c = 0; c < size; c++) row.push(code.modules[r][c] ? 1 : 0);
        matrix.push(row);
    }
    return matrix;
}

// ── PNG renderer ────────────────────────────────────────────────────
// Bulletproof fallback: writes a real PNG buffer the user can scan from
// Preview, a phone gallery, or anywhere. Pure built-ins (node:zlib);
// no third-party deps.

const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        t[n] = c >>> 0;
    }
    return t;
})();
function crc32(buf) {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
}
function pngChunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const t = Buffer.from(type, 'ascii');
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
    return Buffer.concat([len, t, data, crc]);
}

function toPng(text, opts = {}) {
    const matrix = buildMatrix(text);
    const scale = opts.scale ?? 12;
    const quiet = opts.quietZone ?? 4;
    const size = matrix.length;
    const total = size + 2 * quiet;
    const W = total * scale, H = total * scale;
    // 8-bit grayscale, one filter byte per scanline.
    const stride = 1 + W;
    const raw = Buffer.alloc(H * stride);
    for (let r = 0; r < H; r++) {
        raw[r * stride] = 0; // filter: None
        const mr = Math.floor(r / scale) - quiet;
        for (let c = 0; c < W; c++) {
            const mc = Math.floor(c / scale) - quiet;
            const dark = mr >= 0 && mr < size && mc >= 0 && mc < size && matrix[mr][mc];
            raw[r * stride + 1 + c] = dark ? 0 : 255;
        }
    }
    const idat = zlib.deflateSync(raw);
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(W, 0);
    ihdr.writeUInt32BE(H, 4);
    ihdr.writeUInt8(8, 8);   // bit depth
    ihdr.writeUInt8(0, 9);   // color type: grayscale
    ihdr.writeUInt8(0, 10);  // compression: deflate
    ihdr.writeUInt8(0, 11);  // filter: standard
    ihdr.writeUInt8(0, 12);  // interlace: none
    const sig = Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    return Buffer.concat([
        sig,
        pngChunk('IHDR', ihdr),
        pngChunk('IDAT', idat),
        pngChunk('IEND', Buffer.alloc(0))
    ]);
}

module.exports = { generate, toPng, buildMatrix };
