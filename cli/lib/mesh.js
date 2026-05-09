'use strict';

const http = require('node:http');
const ui = require('./ui');
const { BRIDGE_HTTP_PORT } = require('./platform');

function request(method, path, body) {
  const payload = body ? Buffer.from(JSON.stringify(body)) : null;
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1',
      port: BRIDGE_HTTP_PORT,
      method,
      path,
      headers: payload ? {
        'Content-Type': 'application/json',
        'Content-Length': payload.length
      } : {}
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf8');
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(raw || `mesh request failed (${res.statusCode})`));
          return;
        }
        try {
          resolve(raw ? JSON.parse(raw) : {});
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function value(args, name, fallback = null) {
  const idx = args.indexOf(name);
  if (idx === -1 || idx + 1 >= args.length) return fallback;
  return args[idx + 1];
}

function help() {
  process.stdout.write(`
${ui.bold('usage')}
  clawix mesh identity [--json]
  clawix mesh peers [--json]
  clawix mesh link --host <host> --token <pairing-token> [--http-port <port>]
  clawix mesh allow --path <path> [--label <name>]
  clawix mesh workspaces [--json]
  clawix mesh start-job --peer <node-id> --workspace <path> --prompt <text> [--json]
  clawix mesh job --id <job-id> [--json]
`);
}

async function run(args, { json = false } = {}) {
  const cmd = args[0] || 'help';
  if (cmd === 'help' || cmd === '--help' || cmd === '-h') {
    help();
    return;
  }

  if (cmd === 'identity') {
    const out = await request('GET', '/mesh/identity');
    print(out, json);
    return;
  }

  if (cmd === 'peers') {
    const out = await request('GET', '/mesh/peers');
    if (json) return print(out, true);
    for (const peer of out.peers || []) {
      const status = peer.revokedAt ? 'revoked' : 'paired';
      process.stdout.write(`${peer.nodeId}  ${peer.displayName}  ${status}  ${peer.permissionProfile}\n`);
    }
    return;
  }

  if (cmd === 'link') {
    const host = value(args, '--host');
    const token = value(args, '--token');
    const httpPort = Number(value(args, '--http-port', '7779'));
    if (!host || !token) throw new Error('mesh link requires --host and --token');
    const out = await request('POST', '/mesh/link', { host, httpPort, token });
    if (json) return print(out, true);
    process.stdout.write(`linked ${out.peer.displayName} (${out.peer.nodeId})\n`);
    return;
  }

  if (cmd === 'allow') {
    const path = value(args, '--path');
    const label = value(args, '--label');
    if (!path) throw new Error('mesh allow requires --path');
    const out = await request('POST', '/mesh/workspaces', { path, label });
    if (json) return print(out, true);
    process.stdout.write(`allowed ${out.workspace.path}\n`);
    return;
  }

  if (cmd === 'workspaces') {
    const out = await request('GET', '/mesh/workspaces');
    if (json) return print(out, true);
    for (const workspace of out.workspaces || []) {
      process.stdout.write(`${workspace.path}  ${workspace.label}\n`);
    }
    return;
  }

  if (cmd === 'start-job') {
    const peerId = value(args, '--peer');
    const workspacePath = value(args, '--workspace');
    const prompt = value(args, '--prompt');
    if (!peerId || !workspacePath || !prompt) {
      throw new Error('mesh start-job requires --peer, --workspace, and --prompt');
    }
    const out = await request('POST', '/mesh/remote-jobs', { peerId, workspacePath, prompt });
    if (json) return print(out, true);
    process.stdout.write(`started remote job ${out.job.id} on ${peerId}\n`);
    return;
  }

  if (cmd === 'job') {
    const id = value(args, '--id');
    if (!id) throw new Error('mesh job requires --id');
    const out = await request('GET', `/mesh/jobs/${encodeURIComponent(id)}`);
    if (json) return print(out, true);
    if (!out.job) {
      process.stdout.write('job not found\n');
      return;
    }
    process.stdout.write(`${out.job.id}  ${out.job.status}\n`);
    for (const event of out.events || []) {
      process.stdout.write(`  ${event.type}: ${event.message}\n`);
    }
    return;
  }

  throw new Error(`unknown mesh command "${cmd}"`);
}

function print(value, json) {
  if (json) {
    process.stdout.write(JSON.stringify(value, null, 2) + '\n');
    return;
  }
  process.stdout.write(JSON.stringify(value, null, 2) + '\n');
}

module.exports = { run };
