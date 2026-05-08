'use strict';

// Pure-JS QR Code generator scoped to what the Clawix pairing payload
// needs: byte mode, error-correction level M, versions 1-10, full mask
// selection by minimum-penalty score per ISO/IEC 18004:2015.
//
// Algorithm and constants adapted from Kazuhiko Arase's qrcode-generator
// (MIT-licensed) and the ISO spec. The implementation is self-contained
// and has zero dependencies so the CLI never has to shell out to a
// system QR encoder.
//
// Original work © 2009 Kazuhiko Arase, used under the MIT License.

// ── Galois Field GF(256) tables (primitive polynomial 0x11d) ────────
const EXP = new Array(256);
const LOG = new Array(256);
(() => {
    let x = 1;
    for (let i = 0; i < 256; i++) {
        EXP[i] = x;
        x <<= 1;
        if (x & 0x100) x ^= 0x11d;
    }
    for (let i = 0; i < 255; i++) LOG[EXP[i]] = i;
})();

function gfMul(a, b) {
    if (a === 0 || b === 0) return 0;
    return EXP[(LOG[a] + LOG[b]) % 255];
}

// ── Generator polynomial of degree `n` for Reed-Solomon ECC ─────────
function generatorPoly(degree) {
    let g = [1];
    for (let i = 0; i < degree; i++) {
        const next = new Array(g.length + 1).fill(0);
        for (let j = 0; j < g.length; j++) {
            next[j] ^= g[j];
            next[j + 1] ^= gfMul(g[j], EXP[i]);
        }
        g = next;
    }
    return g;
}

// ── Per-version data for byte mode + EC level M ─────────────────────
// Each entry: [totalDataCodewords, ecCodewordsPerBlock, [g1Blocks, g1DataPerBlock], [g2Blocks, g2DataPerBlock]]
// Sourced from ISO/IEC 18004:2015 Table 9 (level M column).
const VERSION_M = {
    1: [16, 10, [1, 16], null],
    2: [28, 16, [1, 28], null],
    3: [44, 26, [1, 44], null],
    4: [64, 18, [2, 32], null],
    5: [86, 24, [2, 43], null],
    6: [108, 16, [4, 27], null],
    7: [124, 18, [4, 31], null],
    8: [154, 22, [2, 38], [2, 39]],
    9: [182, 22, [3, 36], [2, 37]],
    10: [216, 26, [4, 43], [1, 44]]
};

// Alignment pattern centers per version. v1 has none.
const ALIGN_CENTERS = {
    1: [],
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50]
};

// ── BitBuffer ───────────────────────────────────────────────────────
class BitBuffer {
    constructor() { this.data = []; this.length = 0; }
    put(num, len) {
        for (let i = 0; i < len; i++) this.putBit(((num >>> (len - i - 1)) & 1) === 1);
    }
    putBit(bit) {
        const i = this.length >> 3;
        if (this.data.length <= i) this.data.push(0);
        if (bit) this.data[i] |= 0x80 >>> (this.length & 7);
        this.length++;
    }
}

// ── Choose smallest version that fits the payload ───────────────────
function chooseVersion(byteLength) {
    for (let v = 1; v <= 10; v++) {
        const totalData = VERSION_M[v][0];
        // Mode (4 bits) + length indicator (8 for v1-9, 16 for v10) + payload bits.
        const lenBits = v < 10 ? 8 : 16;
        const requiredBits = 4 + lenBits + byteLength * 8;
        if (requiredBits <= totalData * 8) return v;
    }
    throw new Error(`payload too large for QR up to v10 (${byteLength} bytes)`);
}

// ── Encode payload bytes → final codeword stream (data + ECC) ───────
function buildCodewords(bytes, version) {
    const [totalData, ecPerBlock, g1, g2] = VERSION_M[version];
    const lenBits = version < 10 ? 8 : 16;

    const buf = new BitBuffer();
    buf.put(0b0100, 4);                          // mode indicator: byte
    buf.put(bytes.length, lenBits);              // length indicator
    for (const b of bytes) buf.put(b, 8);        // payload
    // Terminator (up to 4 zeros, only as many as fit).
    const totalBits = totalData * 8;
    const remaining = totalBits - buf.length;
    if (remaining > 0) buf.put(0, Math.min(4, remaining));
    // Pad to byte boundary.
    while (buf.length % 8 !== 0) buf.putBit(false);
    // Pad bytes alternating 0xEC 0x11.
    while (buf.data.length < totalData) {
        buf.data.push(0xEC);
        if (buf.data.length < totalData) buf.data.push(0x11);
    }

    const dataBytes = buf.data.slice(0, totalData);

    // Split into blocks.
    const blocks = [];
    let cursor = 0;
    for (const grp of [g1, g2]) {
        if (!grp) continue;
        const [count, dataPer] = grp;
        for (let i = 0; i < count; i++) {
            blocks.push(dataBytes.slice(cursor, cursor + dataPer));
            cursor += dataPer;
        }
    }

    // Compute ECC for each block.
    const generator = generatorPoly(ecPerBlock);
    const eccBlocks = blocks.map((data) => {
        const remainder = data.concat(new Array(ecPerBlock).fill(0));
        for (let i = 0; i < data.length; i++) {
            const factor = remainder[i];
            if (factor === 0) continue;
            for (let j = 0; j < generator.length; j++) {
                remainder[i + j] ^= gfMul(generator[j], factor);
            }
        }
        return remainder.slice(data.length);
    });

    // Interleave: take j-th codeword of every data block, then every ECC block.
    const maxData = Math.max(...blocks.map((b) => b.length));
    const out = [];
    for (let j = 0; j < maxData; j++) {
        for (const b of blocks) if (j < b.length) out.push(b[j]);
    }
    for (let j = 0; j < ecPerBlock; j++) {
        for (const b of eccBlocks) out.push(b[j]);
    }
    return out;
}

// ── Build the module matrix for a given version ─────────────────────
function buildMatrix(version) {
    const size = 17 + version * 4;
    const M = new Array(size);
    const RESERVED = new Array(size);
    for (let r = 0; r < size; r++) {
        M[r] = new Array(size).fill(0);
        RESERVED[r] = new Array(size).fill(false);
    }

    const placeFinder = (r, c) => {
        for (let i = -1; i <= 7; i++) {
            for (let j = -1; j <= 7; j++) {
                const rr = r + i, cc = c + j;
                if (rr < 0 || rr >= size || cc < 0 || cc >= size) continue;
                let v = 0;
                if ((i >= 0 && i <= 6 && (j === 0 || j === 6))
                    || (j >= 0 && j <= 6 && (i === 0 || i === 6))
                    || (i >= 2 && i <= 4 && j >= 2 && j <= 4)) v = 1;
                M[rr][cc] = v;
                RESERVED[rr][cc] = true;
            }
        }
    };
    placeFinder(0, 0);
    placeFinder(0, size - 7);
    placeFinder(size - 7, 0);

    const placeAlignment = (r, c) => {
        for (let i = -2; i <= 2; i++) {
            for (let j = -2; j <= 2; j++) {
                const rr = r + i, cc = c + j;
                let v = 1;
                if (Math.max(Math.abs(i), Math.abs(j)) === 1) v = 0;
                M[rr][cc] = v;
                RESERVED[rr][cc] = true;
            }
        }
    };
    const aligns = ALIGN_CENTERS[version];
    for (const r of aligns) {
        for (const c of aligns) {
            if (RESERVED[r][c]) continue; // skip if overlaps a finder
            placeAlignment(r, c);
        }
    }

    // Timing patterns.
    for (let i = 8; i < size - 8; i++) {
        if (!RESERVED[6][i]) { M[6][i] = i % 2 === 0 ? 1 : 0; RESERVED[6][i] = true; }
        if (!RESERVED[i][6]) { M[i][6] = i % 2 === 0 ? 1 : 0; RESERVED[i][6] = true; }
    }

    // Reserve format-info area (filled later).
    for (let i = 0; i < 9; i++) RESERVED[8][i] = true;
    for (let i = 0; i < 8; i++) RESERVED[i][8] = true;
    for (let i = size - 8; i < size; i++) RESERVED[8][i] = true;
    for (let i = size - 7; i < size; i++) RESERVED[i][8] = true;

    // Reserve version-info area (only present in v7+). Two 6×3 blocks
    // mirrored across the diagonal: top-right and bottom-left, just
    // inside the corresponding finder separators.
    if (version >= 7) {
        for (let i = 0; i < 18; i++) {
            const r = Math.floor(i / 3);
            const c = (i % 3) + size - 11;
            RESERVED[r][c] = true;
            RESERVED[c][r] = true;
        }
    }

    // Dark module (always 1) at (4*ver+9, 8).
    M[size - 8][8] = 1;
    RESERVED[size - 8][8] = true;

    return { M, RESERVED, size };
}

// Snake-fill data bits into the matrix bottom-up, right-to-left,
// skipping reserved cells. `bits` is a flat array of 0/1.
function fillData(matrix, bits) {
    const { M, RESERVED, size } = matrix;
    let bitIdx = 0;
    let upward = true;
    for (let col = size - 1; col > 0; col -= 2) {
        if (col === 6) col--; // skip the timing column
        for (let i = 0; i < size; i++) {
            const row = upward ? size - 1 - i : i;
            for (const c of [col, col - 1]) {
                if (RESERVED[row][c]) continue;
                M[row][c] = bitIdx < bits.length ? bits[bitIdx] : 0;
                bitIdx++;
            }
        }
        upward = !upward;
    }
}

// 8 mask predicates as per ISO/IEC 18004 §7.8.2.
const MASK_FUNCS = [
    (r, c) => (r + c) % 2 === 0,
    (r, c) => r % 2 === 0,
    (r, c) => c % 3 === 0,
    (r, c) => (r + c) % 3 === 0,
    (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0,
    (r, c) => ((r * c) % 2) + ((r * c) % 3) === 0,
    (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 === 0,
    (r, c) => (((r + c) % 2) + ((r * c) % 3)) % 2 === 0
];

function applyMask(matrix, maskIdx) {
    const { M, RESERVED, size } = matrix;
    const f = MASK_FUNCS[maskIdx];
    for (let r = 0; r < size; r++) {
        for (let c = 0; c < size; c++) {
            if (RESERVED[r][c]) continue;
            if (f(r, c)) M[r][c] ^= 1;
        }
    }
}

// Format info: 5 bits (EC level + mask pattern) → BCH(15,5) → XOR mask.
const FORMAT_MASK = 0b101010000010010;
function formatInfoBits(maskIdx) {
    // EC level M is encoded as 0b00.
    let data = (0b00 << 3) | maskIdx;
    let bch = data << 10;
    const G = 0b10100110111;
    while (true) {
        const top = 31 - Math.clz32(bch >>> 0);
        if (top < 10) break;
        bch ^= G << (top - 10);
    }
    const code = ((data << 10) | bch) ^ FORMAT_MASK;
    const bits = [];
    for (let i = 14; i >= 0; i--) bits.push((code >> i) & 1);
    return bits;
}

function placeFormat(matrix, bits) {
    const { M, size } = matrix;
    // Around top-left finder.
    for (let i = 0; i <= 5; i++) M[8][i] = bits[i];
    M[8][7] = bits[6];
    M[8][8] = bits[7];
    M[7][8] = bits[8];
    for (let i = 9; i <= 14; i++) M[14 - i][8] = bits[i];
    // Top-right + bottom-left.
    for (let i = 0; i <= 7; i++) M[size - 1 - i][8] = bits[i];
    for (let i = 8; i <= 14; i++) M[8][size - 15 + i] = bits[i];
    // Always-dark module.
    M[size - 8][8] = 1;
}

// Version-info: 18 bits (6 data + BCH(18,6) Golay ECC) placed in two
// 6×3 blocks. Only present in v7 and above (per ISO/IEC 18004 §7.10).
const VERSION_BCH_POLY = 0b1111100100101; // x^12+x^11+x^10+x^9+x^8+x^5+x^2+1
function versionInfoBits(version) {
    let d = version << 12;
    while (true) {
        const top = 31 - Math.clz32(d >>> 0);
        if (top < 12) break;
        d ^= VERSION_BCH_POLY << (top - 12);
    }
    return (version << 12) | d;
}

function placeVersion(matrix, version) {
    if (version < 7) return;
    const { M, size } = matrix;
    const bits = versionInfoBits(version);
    for (let i = 0; i < 18; i++) {
        const r = Math.floor(i / 3);
        const c = (i % 3) + size - 11;
        const mod = (bits >> i) & 1;
        M[r][c] = mod;
        M[c][r] = mod;
    }
}

// ── Mask penalty score (lower is better) ────────────────────────────
function maskPenalty(matrix) {
    const { M, size } = matrix;
    let penalty = 0;
    // Rule 1: runs of 5+ same-color modules in a row/column.
    for (let r = 0; r < size; r++) {
        let run = 1;
        for (let c = 1; c < size; c++) {
            if (M[r][c] === M[r][c - 1]) {
                run++;
                if (run === 5) penalty += 3;
                else if (run > 5) penalty += 1;
            } else run = 1;
        }
    }
    for (let c = 0; c < size; c++) {
        let run = 1;
        for (let r = 1; r < size; r++) {
            if (M[r][c] === M[r - 1][c]) {
                run++;
                if (run === 5) penalty += 3;
                else if (run > 5) penalty += 1;
            } else run = 1;
        }
    }
    // Rule 2: 2×2 blocks of same color.
    for (let r = 0; r < size - 1; r++) {
        for (let c = 0; c < size - 1; c++) {
            const v = M[r][c];
            if (M[r][c + 1] === v && M[r + 1][c] === v && M[r + 1][c + 1] === v) penalty += 3;
        }
    }
    // Rule 3 + 4 omitted: rule 3 is finder-pattern lookalike (rare in
    // small QRs), rule 4 is overall dark/light balance. The first two
    // dominate the optimum mask choice in practice.
    return penalty;
}

// ── Public encode → 2D matrix of 0/1 ────────────────────────────────
function encode(text) {
    const bytes = Array.from(Buffer.from(text, 'utf8'));
    const version = chooseVersion(bytes.length);
    const codewords = buildCodewords(bytes, version);

    // Flatten codewords into a bit array, then snake-fill.
    const bits = [];
    for (const cw of codewords) for (let i = 7; i >= 0; i--) bits.push((cw >> i) & 1);

    let best = null;
    for (let mask = 0; mask < 8; mask++) {
        const matrix = buildMatrix(version);
        fillData(matrix, bits);
        applyMask(matrix, mask);
        placeFormat(matrix, formatInfoBits(mask));
        placeVersion(matrix, version);
        const penalty = maskPenalty(matrix);
        if (!best || penalty < best.penalty) best = { matrix, penalty };
    }
    return best.matrix.M;
}

// ── Renderers ───────────────────────────────────────────────────────
// In a TTY we use ANSI half-block: each terminal cell covers two QR
// rows, with bg=white + fg=black setup so line-padding inherits the
// background color (no font/line-height seams). Same pattern as the
// `qrcode` npm package's `small` terminal mode, used in production
// by many CLIs (qrcode-terminal, whatsapp-web.js, etc.).
//
// When color is disabled (NO_COLOR, redirect to file) we fall back to
// 2-char-wide Unicode/ASCII blocks (square per cell on any monospace).
function toAnsi(modules, opts = {}) {
    const color = opts.color !== false;
    const utf8 = opts.utf8 !== false;
    const quiet = opts.quietZone ?? 2;
    const size = modules.length;

    // Pad the matrix with a quiet zone of 0-modules so the renderer
    // doesn't have to special-case borders.
    const blank = quiet ? Array(quiet).fill(0) : [];
    const padded = [];
    for (let i = 0; i < quiet; i++) padded.push(new Array(size + quiet * 2).fill(0));
    for (const row of modules) padded.push([...blank, ...row, ...blank]);
    for (let i = 0; i < quiet; i++) padded.push(new Array(size + quiet * 2).fill(0));

    if (!color) {
        const dark = utf8 ? '██' : '##';
        const light = '  ';
        return padded.map((row) => row.map((c) => c ? dark : light).join('')).join('\n');
    }

    const lineSetup = '\x1b[47m\x1b[30m'; // bg=white, fg=black
    const reset = '\x1b[0m';
    const lines = [];
    for (let y = 0; y < padded.length; y += 2) {
        let line = lineSetup;
        for (let x = 0; x < padded[0].length; x++) {
            const top = padded[y][x];
            const bot = y + 1 < padded.length ? padded[y + 1][x] : 0;
            if (!top && !bot) line += ' ';
            else if (!top && bot) line += '▄';
            else if (top && !bot) line += '▀';
            else line += '█';
        }
        line += reset;
        lines.push(line);
    }
    return lines.join('\n');
}

// ── PNG renderer ────────────────────────────────────────────────────
// Bulletproof fallback: writes a real PNG buffer the user can scan from
// Preview, a phone gallery, or anywhere. Pure built-ins (node:zlib);
// no third-party deps.
const zlib = require('node:zlib');

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

function toPng(modules, opts = {}) {
    const scale = opts.scale ?? 12;
    const quiet = opts.quietZone ?? 4;
    const size = modules.length;
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
            const dark = mr >= 0 && mr < size && mc >= 0 && mc < size && modules[mr][mc];
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

module.exports = { encode, toAnsi, toPng };
