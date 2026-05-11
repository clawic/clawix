'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { call, invokeTool, printJSON, printTable, parseFlag, hasFlag } = require('./iot-client');

const HELP = `\
clawix scenes — list and activate scenes

usage
  clawix scenes ls [--home <id>] [--json]
  clawix scenes activate <scene-id>
  clawix scenes create --file <path>
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
    case 'activate':
      return activate(rest);
    case 'create':
      return create(rest, { json });
    default:
      throw new Error(`unknown subcommand "${sub}". Run \`clawix scenes --help\`.`);
  }
}

async function ls(args, { json }) {
  const homeId = parseFlag(args, '--home');
  const path = homeId ? `/v1/homes/${encodeURIComponent(homeId)}/scenes` : '/v1/scenes';
  const response = await call('GET', path);
  const scenes = response.scenes || [];
  if (json) {
    printJSON({ scenes });
    return;
  }
  printTable(
    ['id', 'label', 'actions', 'description'],
    scenes.map((scene) => [scene.id, scene.label, (scene.actions || []).length, scene.description || '—']),
  );
}

async function activate(args) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error('clawix scenes activate <scene-id>');
  const response = await call('POST', `/v1/scenes/${encodeURIComponent(id)}/activate`);
  process.stdout.write(`activated: ${id} · ${response.result?.status || 'unknown'}\n`);
}

async function create(args, { json }) {
  const filePath = parseFlag(args, '--file');
  if (!filePath) throw new Error('clawix scenes create --file <path>');
  const absolute = path.resolve(process.cwd(), filePath);
  if (!fs.existsSync(absolute)) throw new Error(`scene file not found: ${absolute}`);
  // The daemon does not yet expose a "create scene" REST route; we use
  // the raw policy evaluation surface to dry-run + bail. When the
  // create route lands the call site swaps in.
  throw new Error('scenes create is not implemented on the daemon yet. Use the GUI editor (Phase 4 backlog).');
}

module.exports = { run };
