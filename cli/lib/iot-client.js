'use strict';

// HTTP client shared by every `clawix <iot-noun>` subcommand. Talks
// directly to the clawjs-iot daemon on loopback (port 7795). When the
// daemon is not reachable we surface a clear error pointing the user
// at `clawix doctor` and Clawix.app, since the daemon is spawned by
// the app's supervisor today (see ClawJSServiceManager).

const http = require('node:http');

const IOT_HTTP_HOST = '127.0.0.1';
const IOT_HTTP_PORT = 7795;

/** Send a request to the daemon and parse the JSON response.
 *  Resolves with { status, body }. Rejects only on transport errors
 *  (refused connection, timeout). Non-2xx HTTP statuses come back via
 *  the resolved body so callers decide how to surface them.
 */
function request(method, path, body) {
  const payload = body ? Buffer.from(JSON.stringify(body)) : null;
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: IOT_HTTP_HOST,
        port: IOT_HTTP_PORT,
        method,
        path,
        headers: payload
          ? { 'Content-Type': 'application/json', 'Content-Length': payload.length }
          : {},
        timeout: 8000,
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          const raw = Buffer.concat(chunks).toString('utf8');
          let parsed = null;
          if (raw.length > 0) {
            try {
              parsed = JSON.parse(raw);
            } catch {
              parsed = raw;
            }
          }
          resolve({ status: res.statusCode || 0, body: parsed });
        });
      },
    );
    req.on('error', (err) => reject(err));
    req.on('timeout', () => {
      req.destroy(new Error('IoT daemon request timed out.'));
    });
    if (payload) req.write(payload);
    req.end();
  });
}

/** Wrap `request` and throw a helpful error when the daemon is not
 *  reachable. Most subcommands call this directly. */
async function call(method, path, body) {
  let response;
  try {
    response = await request(method, path, body);
  } catch (err) {
    if (err && (err.code === 'ECONNREFUSED' || err.code === 'EHOSTUNREACH')) {
      const helper = new Error(
        `IoT daemon not reachable on ${IOT_HTTP_HOST}:${IOT_HTTP_PORT}. ` +
          `Start Clawix.app (its supervisor spawns the iot service) or run \`clawix up\` first.`,
      );
      helper.code = 'IOT_UNREACHABLE';
      throw helper;
    }
    throw err;
  }
  if (response.status >= 400) {
    const errorBody = typeof response.body === 'object' && response.body !== null
      ? JSON.stringify(response.body)
      : String(response.body || '');
    const err = new Error(`IoT daemon returned HTTP ${response.status}: ${errorBody}`);
    err.code = 'IOT_HTTP_ERROR';
    err.status = response.status;
    throw err;
  }
  return response.body;
}

/** Invoke a tool via the registry endpoint. Returns the unwrapped
 *  value or throws when the daemon reports `ok: false`. */
async function invokeTool(toolId, args) {
  const result = await call('POST', `/v1/tools/${encodeURIComponent(toolId)}/invoke`, { arguments: args || {} });
  if (!result || result.ok === false) {
    const detail = result && result.error ? `${result.error.code}: ${result.error.message}` : 'unknown error';
    const err = new Error(`Tool ${toolId} failed: ${detail}`);
    err.code = 'IOT_TOOL_FAILURE';
    throw err;
  }
  return result.value;
}

/** Print JSON exactly like the existing `clawix status --json` flag.
 *  Centralised so every subcommand stays uniform. */
function printJSON(payload) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
}

/** Print a simple aligned table. Each `row` is an array of strings.
 *  When no rows are supplied we print "(no rows)" so the CLI never
 *  drops the user into an empty terminal.
 */
function printTable(headers, rows) {
  if (rows.length === 0) {
    process.stdout.write('(no rows)\n');
    return;
  }
  const widths = headers.map((header, index) => Math.max(
    header.length,
    ...rows.map((row) => String(row[index] ?? '').length),
  ));
  const formatRow = (row) => row
    .map((cell, index) => String(cell ?? '').padEnd(widths[index]))
    .join('  ');
  process.stdout.write(`${formatRow(headers)}\n`);
  process.stdout.write(`${formatRow(headers.map((_, i) => '─'.repeat(widths[i])))}\n`);
  for (const row of rows) {
    process.stdout.write(`${formatRow(row)}\n`);
  }
}

function parseFlag(args, name) {
  const index = args.indexOf(name);
  if (index === -1) return undefined;
  return args[index + 1];
}

function hasFlag(args, name) {
  return args.includes(name);
}

module.exports = {
  IOT_HTTP_HOST,
  IOT_HTTP_PORT,
  request,
  call,
  invokeTool,
  printJSON,
  printTable,
  parseFlag,
  hasFlag,
};
