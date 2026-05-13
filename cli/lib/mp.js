'use strict';

// Phase 1 CLI for the mp/1.0.0 marketplace protocol. Talks to the
// @clawjs/index daemon over loopback HTTP using the admin token written
// by Clawix.app's supervisor on first launch.
//
// Subcommands:
//   clawix mp status                        daemon + identity snapshot
//   clawix mp identity list                 list root keys, devices, roles
//   clawix mp roles list                    list roles
//   clawix mp intents list [--side offer|want]
//                                           list intents
//   clawix mp intents status <id> <status>  update intent status
//   clawix mp inbox list                    list pending inbound messages
//   clawix mp receipts list                 list match receipts
//   clawix mp brokers list                  list known brokers
//
// All operations are read-mostly. Mutations that require cryptographic
// signing live in the daemon-side @clawjs/mp package, not here.

const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');

const INDEX_HOST = '127.0.0.1';
const INDEX_PORT = 7796;

function workspaceRoot() {
    if (process.env.CLAWIX_DUMMY_MODE === '1' && process.env.CLAWIX_CLAW_ROOT) {
        return process.env.CLAWIX_CLAW_ROOT;
    }
    return path.join(os.homedir(), 'Library/Application Support/Clawix/clawjs');
}

function indexDataDir() {
    return path.join(workspaceRoot(), 'workspace/.claw/index');
}

function readAdminToken() {
    const fromEnv = process.env.CLAWJS_INDEX_ADMIN_TOKEN;
    if (fromEnv && fromEnv.trim()) return fromEnv.trim();
    const file = path.join(indexDataDir(), '.admin-token');
    if (!fs.existsSync(file)) return null;
    const raw = fs.readFileSync(file, 'utf8').trim();
    return raw.length >= 32 ? raw : null;
}

function request(method, urlPath, body) {
    return new Promise((resolve, reject) => {
        const token = readAdminToken();
        if (!token) {
            reject(new Error('Index daemon admin token not found. Is Clawix.app running?'));
            return;
        }
        const req = http.request({
            host: INDEX_HOST,
            port: INDEX_PORT,
            path: urlPath,
            method,
            headers: Object.assign(
                {
                    Accept: 'application/json',
                    Authorization: `Bearer ${token}`,
                },
                body ? { 'Content-Type': 'application/json' } : {},
            ),
        }, (res) => {
            const chunks = [];
            res.on('data', (chunk) => chunks.push(chunk));
            res.on('end', () => {
                const buf = Buffer.concat(chunks).toString('utf8');
                if (res.statusCode < 200 || res.statusCode >= 300) {
                    reject(new Error(`HTTP ${res.statusCode}: ${buf}`));
                    return;
                }
                if (!buf) { resolve({}); return; }
                try { resolve(JSON.parse(buf)); }
                catch (err) { reject(err); }
            });
        });
        req.on('error', reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

async function statusCmd(flags) {
    const out = {};
    try {
        const health = await request('GET', '/v1/health');
        out.daemon = { reachable: true, ...health };
    } catch (err) {
        out.daemon = { reachable: false, error: err.message };
    }
    try {
        const r = await request('GET', '/v1/mp/identity/roots');
        out.rootKeys = r.roots.length;
    } catch (err) {
        out.rootKeys = `error: ${err.message}`;
    }
    try {
        const r = await request('GET', '/v1/mp/identity/devices');
        out.devices = r.devices.length;
    } catch (err) {
        out.devices = `error: ${err.message}`;
    }
    try {
        const r = await request('GET', '/v1/mp/identity/roles');
        out.roles = r.roles.length;
    } catch (err) {
        out.roles = `error: ${err.message}`;
    }
    try {
        const r = await request('GET', '/v1/mp/intents');
        out.intents = r.intents.length;
    } catch (err) {
        out.intents = `error: ${err.message}`;
    }
    try {
        const r = await request('GET', '/v1/mp/mailbox/inbound');
        out.inbox = r.messages.length;
    } catch (err) {
        out.inbox = `error: ${err.message}`;
    }
    if (flags.json) {
        console.log(JSON.stringify(out, null, 2));
    } else {
        console.log(`daemon       : ${out.daemon.reachable ? 'reachable' : 'unreachable'} (${INDEX_HOST}:${INDEX_PORT})`);
        console.log(`root keys    : ${out.rootKeys}`);
        console.log(`devices      : ${out.devices}`);
        console.log(`roles        : ${out.roles}`);
        console.log(`intents      : ${out.intents}`);
        console.log(`inbox        : ${out.inbox}`);
    }
}

async function identityListCmd(flags) {
    const [roots, devices, roles] = await Promise.all([
        request('GET', '/v1/mp/identity/roots'),
        request('GET', '/v1/mp/identity/devices'),
        request('GET', '/v1/mp/identity/roles'),
    ]);
    if (flags.json) {
        console.log(JSON.stringify({ roots: roots.roots, devices: devices.devices, roles: roles.roles }, null, 2));
        return;
    }
    console.log('Root keys');
    for (const r of roots.roots) {
        console.log(`  ${r.id}  ${r.label || '(no label)'}  pub:${shortPub(r.pubkey)}`);
    }
    console.log('Devices');
    for (const d of devices.devices) {
        console.log(`  ${d.id}  ${d.deviceName}  pub:${shortPub(d.pubkey)}${d.revokedAt ? '  (revoked)' : ''}`);
    }
    console.log('Roles');
    for (const r of roles.roles) {
        console.log(`  ${r.id}  ${r.roleName}  vertical:${r.vertical}  pub:${shortPub(r.pubkey)}${r.revokedAt ? '  (revoked)' : ''}`);
    }
}

async function rolesListCmd(flags) {
    const resp = await request('GET', '/v1/mp/identity/roles');
    if (flags.json) {
        console.log(JSON.stringify(resp.roles, null, 2));
        return;
    }
    if (resp.roles.length === 0) {
        console.log('no roles');
        return;
    }
    for (const r of resp.roles) {
        console.log(`  ${r.id}  ${r.roleName}  vertical:${r.vertical}  pub:${shortPub(r.pubkey)}${r.revokedAt ? '  (revoked)' : ''}`);
    }
}

async function intentsListCmd(args, flags) {
    const query = [];
    const sideIdx = args.indexOf('--side');
    if (sideIdx >= 0) query.push(`side=${args[sideIdx + 1]}`);
    const verticalIdx = args.indexOf('--vertical');
    if (verticalIdx >= 0) query.push(`vertical=${args[verticalIdx + 1]}`);
    const provIdx = args.indexOf('--provenance');
    if (provIdx >= 0) query.push(`provenance=${args[provIdx + 1]}`);
    const suffix = query.length ? `?${query.join('&')}` : '';
    const resp = await request('GET', `/v1/mp/intents${suffix}`);
    if (flags.json) {
        console.log(JSON.stringify(resp.intents, null, 2));
        return;
    }
    if (resp.intents.length === 0) {
        console.log('no intents');
        return;
    }
    for (const intent of resp.intents) {
        const title = intent.payload && intent.payload.title ? intent.payload.title : '(untitled)';
        const tag = intent.provenance === 'native' ? 'verified' : 'observed';
        console.log(`  ${intent.id}  ${intent.side}  ${intent.vertical}  [${tag}]  ${intent.status}  ${title}`);
    }
}

async function intentStatusCmd(args) {
    if (args.length < 2) throw new Error('usage: clawix mp intents status <id> <status>');
    const [id, status] = args;
    await request('PATCH', `/v1/mp/intents/${id}/status`, { status });
    console.log(`intent ${id}: status -> ${status}`);
}

async function inboxListCmd(flags) {
    const resp = await request('GET', '/v1/mp/mailbox/inbound');
    if (flags.json) {
        console.log(JSON.stringify(resp.messages, null, 2));
        return;
    }
    if (resp.messages.length === 0) {
        console.log('inbox is empty');
        return;
    }
    for (const m of resp.messages) {
        const text = (m.plaintext && m.plaintext.text) ? `  "${m.plaintext.text.slice(0, 80)}"` : '';
        const read = m.readAt ? '   read' : ' unread';
        console.log(`  ${read}  ${m.kind.padEnd(18)}  from:${shortPub(m.senderPubkey)}  ${m.receivedAt}${text}`);
    }
}

async function receiptsListCmd(flags) {
    const resp = await request('GET', '/v1/mp/match-receipts');
    if (flags.json) {
        console.log(JSON.stringify(resp.receipts, null, 2));
        return;
    }
    if (resp.receipts.length === 0) {
        console.log('no match receipts');
        return;
    }
    for (const r of resp.receipts) {
        console.log(`  ${r.id}  ${r.status}  L${r.reachedLevel}  peer:${shortPub(r.peerRolePubkey)}  fields:${r.fieldsRevealed.join(',')}`);
    }
}

async function brokersListCmd(flags) {
    const resp = await request('GET', '/v1/mp/brokers');
    if (flags.json) {
        console.log(JSON.stringify(resp.brokers, null, 2));
        return;
    }
    if (resp.brokers.length === 0) {
        console.log('no known brokers');
        return;
    }
    for (const b of resp.brokers) {
        console.log(`  ${b.id}  verticals:${b.verticalsSupported.join(',')}  endpoints:${b.endpoints.join(' ')}${b.trustLocal ? '  (trusted)' : ''}`);
    }
}

function shortPub(b64) {
    if (!b64) return '(none)';
    return b64.slice(0, 16) + '…';
}

async function run(args, flags) {
    if (args.length === 0 || args[0] === '--help' || args[0] === '-h' || args[0] === 'help') {
        process.stdout.write(`
clawix mp · marketplace protocol (mp/1.0.0)

  clawix mp status                                daemon + identity snapshot
  clawix mp identity list                         root keys, devices, roles
  clawix mp roles list                            roles only
  clawix mp intents list [--side <s>] [--vertical <v>] [--provenance <p>]
  clawix mp intents status <id> <new-status>      update intent status
  clawix mp inbox list                            pending inbound messages
  clawix mp receipts list                         match receipts
  clawix mp brokers list                          known brokers

Phase 1 surface: read-mostly. Cryptographic operations live in @clawjs/mp.
`);
        return;
    }
    const head = args[0];
    const rest = args.slice(1);
    switch (head) {
        case 'status':         await statusCmd(flags); break;
        case 'identity': {
            if (rest[0] === 'list' || rest.length === 0) await identityListCmd(flags);
            else throw new Error(`unknown identity subcommand "${rest[0]}"`);
            break;
        }
        case 'roles': {
            if (rest[0] === 'list' || rest.length === 0) await rolesListCmd(flags);
            else throw new Error(`unknown roles subcommand "${rest[0]}"`);
            break;
        }
        case 'intents': {
            if (rest[0] === 'list' || rest.length === 0) {
                await intentsListCmd(rest.slice(1), flags);
            } else if (rest[0] === 'status') {
                await intentStatusCmd(rest.slice(1));
            } else {
                throw new Error(`unknown intents subcommand "${rest[0]}"`);
            }
            break;
        }
        case 'inbox':          await inboxListCmd(flags); break;
        case 'receipts':       await receiptsListCmd(flags); break;
        case 'brokers':        await brokersListCmd(flags); break;
        default: throw new Error(`unknown mp subcommand "${head}"`);
    }
}

module.exports = { run };
