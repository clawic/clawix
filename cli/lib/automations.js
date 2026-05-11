'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { call, invokeTool, printJSON, printTable, parseFlag, hasFlag } = require('./iot-client');

const HELP = `\
clawix automations — list, enable, disable, run, create automations

usage
  clawix automations ls [--home <id>] [--json]
  clawix automations enable <automation-id>
  clawix automations disable <automation-id>
  clawix automations run <automation-id>
  clawix automations create --file <path>
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
    case 'enable':
      return setEnabled(rest, true);
    case 'disable':
      return setEnabled(rest, false);
    case 'run':
      return runAutomation(rest);
    case 'create':
      return create(rest, { json });
    default:
      throw new Error(`unknown subcommand "${sub}". Run \`clawix automations --help\`.`);
  }
}

async function ls(args, { json }) {
  const homeId = parseFlag(args, '--home');
  const path = homeId ? `/v1/homes/${encodeURIComponent(homeId)}/automations` : '/v1/automations';
  const response = await call('GET', path);
  const automations = response.automations || [];
  if (json) {
    printJSON({ automations });
    return;
  }
  printTable(
    ['id', 'label', 'enabled', 'actions', 'trigger'],
    automations.map((automation) => [
      automation.id,
      automation.label,
      automation.enabled ? 'yes' : 'no',
      (automation.actions || []).length,
      JSON.stringify(automation.trigger || {}),
    ]),
  );
}

async function setEnabled(args, enabled) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error(`clawix automations ${enabled ? 'enable' : 'disable'} <automation-id>`);
  await call('POST', `/v1/automations/${encodeURIComponent(id)}/${enabled ? 'enable' : 'disable'}`);
  process.stdout.write(`${enabled ? 'enabled' : 'disabled'}: ${id}\n`);
}

async function runAutomation(args) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error('clawix automations run <automation-id>');
  const response = await call('POST', `/v1/automations/${encodeURIComponent(id)}/run`);
  process.stdout.write(`run: ${id} · ${response.result?.status || 'unknown'}\n`);
}

async function create(args, { json }) {
  const filePath = parseFlag(args, '--file');
  if (!filePath) throw new Error('clawix automations create --file <path>');
  const absolute = path.resolve(process.cwd(), filePath);
  if (!fs.existsSync(absolute)) throw new Error(`automation file not found: ${absolute}`);
  const blob = JSON.parse(fs.readFileSync(absolute, 'utf8'));
  const response = await call('POST', '/v1/automations', blob);
  if (json) {
    printJSON(response);
    return;
  }
  process.stdout.write(`created: ${response.automation?.id || '?'}\n`);
}

module.exports = { run };
