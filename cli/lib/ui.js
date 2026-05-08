'use strict';

// TTY-aware presentation primitives. Every helper degrades gracefully:
// no ANSI when stdout isn't a tty or NO_COLOR is set, no unicode bullets
// when the locale isn't UTF-8. Output stays readable in CI logs, redirects
// to files, dumb terminals, and SSH sessions without PTY.

const noColor = !process.stdout.isTTY
    || process.env.NO_COLOR === '1'
    || process.env.NO_COLOR === 'true'
    || process.env.FORCE_COLOR === '0';

const utf8 = (() => {
    const v = (process.env.LC_ALL || process.env.LC_CTYPE || process.env.LANG || '').toLowerCase();
    return v.includes('utf-8') || v.includes('utf8');
})();

function wrap(open, close) {
    return (s) => noColor ? String(s) : `\x1b[${open}m${s}\x1b[${close}m`;
}

const bold = wrap('1', '22');
const dim = wrap('2', '22');
const red = wrap('31', '39');
const green = wrap('32', '39');
const yellow = wrap('33', '39');
const cyan = wrap('36', '39');

const BULLETS = utf8
    ? { ok: '●', warn: '⚠', fail: '✗', hint: '→', done: '✓' }
    : { ok: '*', warn: '!', fail: 'x', hint: '->', done: '+' };

function bullet(level) {
    switch (level) {
    case 'ok': return green(BULLETS.ok);
    case 'warn': return yellow(BULLETS.warn);
    case 'fail': return red(BULLETS.fail);
    case 'done': return green(BULLETS.done);
    case 'hint':
    default: return dim(BULLETS.hint);
    }
}

function section(title) {
    process.stdout.write('\n' + bold(title) + '\n\n');
}

function indent(text, prefix = '  ') {
    return text.split('\n').map((line) => line.length ? prefix + line : line).join('\n');
}

let lastStatusLine = '';
function statusLine(text) {
    if (!process.stdout.isTTY) {
        if (text !== lastStatusLine) {
            console.log(text);
            lastStatusLine = text;
        }
        return;
    }
    process.stdout.write('\r\x1b[2K' + text);
    lastStatusLine = text;
}

function statusLineEnd() {
    if (process.stdout.isTTY && lastStatusLine) {
        process.stdout.write('\n');
    }
    lastStatusLine = '';
}

// Standard error format: "what happened / likely cause / next action".
// Every cli-side error message goes through this so the surface stays
// uniform and the user always knows what to do next.
function fail(what, cause, fix) {
    const lines = [];
    lines.push(red('clawix: ') + what);
    if (cause) lines.push('        ' + cause);
    if (fix) lines.push('        ' + fix);
    process.stderr.write(lines.join('\n') + '\n');
}

module.exports = {
    bold, dim, red, green, yellow, cyan,
    bullet, section, indent, statusLine, statusLineEnd,
    fail,
    isUtf8: utf8,
    isColor: !noColor
};
