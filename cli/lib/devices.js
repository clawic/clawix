'use strict';

// `clawix devices` subcommands. Walks the user through the local
// inventory (`ls`, `get`), the write path (`on`/`off`/`set`), and the
// add / remove / discover flow.

const fs = require('node:fs');
const path = require('node:path');
const { call, invokeTool, printJSON, printTable, parseFlag, hasFlag } = require('./iot-client');

const HELP = `\
clawix devices — list and control IoT devices

usage
  clawix devices ls [--home <id>] [--area <id>] [--kind <kind>] [--json]
  clawix devices get <thing-id> [--json]
  clawix devices on <thing-id>
  clawix devices off <thing-id>
  clawix devices set <thing-id> --capability <key> --value <value>
  clawix devices add --connector <id> [--config-file <path>]
  clawix devices add --fingerprint <fp>
  clawix devices discover [--kind <kind>] [--timeout 8000]
  clawix devices rm <thing-id>
`;

async function run(args, options = {}) {
  const sub = args[0];
  const rest = args.slice(1);
  const json = options.json === true || hasFlag(rest, '--json');
  switch (sub) {
    case undefined:
    case 'help':
    case '--help':
      process.stdout.write(HELP);
      return;
    case 'ls':
      return ls(rest, { json });
    case 'get':
      return get(rest, { json });
    case 'on':
      return setPower(rest, true);
    case 'off':
      return setPower(rest, false);
    case 'set':
      return setCapability(rest);
    case 'add':
      return add(rest, { json });
    case 'discover':
      return discover(rest, { json });
    case 'rm':
    case 'remove':
      return remove(rest);
    default:
      throw new Error(`unknown subcommand "${sub}". Run \`clawix devices --help\`.`);
  }
}

async function ls(args, { json }) {
  const homeId = parseFlag(args, '--home');
  const path = homeId ? `/v1/homes/${encodeURIComponent(homeId)}/things` : '/v1/things';
  const response = await call('GET', path);
  let things = response.things || [];
  const area = parseFlag(args, '--area');
  if (area) things = things.filter((t) => t.areaId === area);
  const kind = parseFlag(args, '--kind');
  if (kind) things = things.filter((t) => t.kind === kind);
  if (json) {
    printJSON({ things });
    return;
  }
  printTable(
    ['id', 'label', 'kind', 'connector', 'risk', 'area'],
    things.map((thing) => [
      thing.id,
      thing.label,
      thing.kind,
      thing.connectorId,
      thing.risk,
      thing.areaId || '—',
    ]),
  );
}

async function get(args, { json }) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error('clawix devices get <thing-id>');
  const response = await call('GET', '/v1/things');
  const thing = (response.things || []).find((t) => t.id === id || t.label === id);
  if (!thing) throw new Error(`unknown thing "${id}"`);
  if (json) {
    printJSON({ thing });
    return;
  }
  process.stdout.write(`${thing.label} (${thing.id})\n`);
  process.stdout.write(`  kind     : ${thing.kind}\n`);
  process.stdout.write(`  risk     : ${thing.risk}\n`);
  process.stdout.write(`  connector: ${thing.connectorId}\n`);
  process.stdout.write(`  target   : ${thing.targetRef}\n`);
  process.stdout.write(`  area     : ${thing.areaId || '—'}\n`);
  process.stdout.write(`  capabilities:\n`);
  for (const capability of thing.capabilities || []) {
    process.stdout.write(`    - ${capability.key} = ${JSON.stringify(capability.observedValue)}${capability.unit ? ' ' + capability.unit : ''}\n`);
  }
}

async function setPower(args, on) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error(`clawix devices ${on ? 'on' : 'off'} <thing-id>`);
  const response = await call('POST', '/v1/actions', {
    action: on ? 'on' : 'off',
    capability: 'power',
    value: on,
    targets: [id],
  });
  process.stdout.write(`status: ${response.result?.status || 'unknown'}\n`);
}

async function setCapability(args) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error('clawix devices set <thing-id> --capability <key> --value <value>');
  const capability = parseFlag(args, '--capability');
  const rawValue = parseFlag(args, '--value');
  if (!capability) throw new Error('--capability is required');
  if (rawValue === undefined) throw new Error('--value is required');
  let value = rawValue;
  if (rawValue === 'true') value = true;
  else if (rawValue === 'false') value = false;
  else if (!Number.isNaN(Number(rawValue))) value = Number(rawValue);
  const response = await call('POST', '/v1/actions', {
    action: 'set',
    capability,
    value,
    targets: [id],
  });
  process.stdout.write(`status: ${response.result?.status || 'unknown'}\n`);
}

async function add(args, { json }) {
  const fingerprint = parseFlag(args, '--fingerprint');
  const connectorId = parseFlag(args, '--connector');
  const configFile = parseFlag(args, '--config-file');
  let toolArgs = {};
  if (fingerprint) {
    toolArgs.fingerprint = fingerprint;
  } else if (connectorId && configFile) {
    const absolute = path.resolve(process.cwd(), configFile);
    if (!fs.existsSync(absolute)) throw new Error(`config file not found: ${absolute}`);
    const blob = JSON.parse(fs.readFileSync(absolute, 'utf8'));
    toolArgs = { ...blob, connectorId };
  } else if (connectorId) {
    toolArgs.connectorId = connectorId;
    const label = parseFlag(args, '--label');
    if (label) toolArgs.label = label;
    const kind = parseFlag(args, '--kind');
    if (kind) toolArgs.kind = kind;
    const targetRef = parseFlag(args, '--target-ref');
    if (targetRef) toolArgs.targetRef = targetRef;
  } else {
    throw new Error('Provide either --fingerprint <fp> or --connector <id> [--config-file <path>]');
  }
  const value = await invokeTool('iot.things.add', toolArgs);
  if (json) {
    printJSON(value);
    return;
  }
  process.stdout.write(`added: ${value?.thing?.id || '?'} (${value?.thing?.label || ''})\n`);
}

async function discover(args, { json }) {
  const kind = parseFlag(args, '--kind');
  const timeoutMs = parseFlag(args, '--timeout');
  await invokeTool('iot.discovery.start', {
    ...(kind ? { kind } : {}),
    ...(timeoutMs ? { timeoutMs: Number(timeoutMs) } : {}),
  });
  await sleep(Number(timeoutMs ?? 4000));
  const value = await invokeTool('iot.discovery.list', {});
  await invokeTool('iot.discovery.stop', {}).catch(() => {});
  if (json) {
    printJSON(value);
    return;
  }
  printTable(
    ['fingerprint', 'label', 'kind', 'connector', 'targetRef'],
    (value?.devices || []).map((d) => [d.fingerprint, d.label, d.kind, d.connectorId, d.targetRef]),
  );
}

async function remove(args) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error('clawix devices rm <thing-id>');
  await invokeTool('iot.things.remove', { thingId: id });
  process.stdout.write(`removed: ${id}\n`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = { run };
