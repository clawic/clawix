'use strict';

const { call, printJSON, printTable, parseFlag, hasFlag } = require('./iot-client');

const HELP = `\
clawix approvals — triage the IoT approval queue

usage
  clawix approvals ls [--home <id>] [--pending] [--json]
  clawix approvals approve <approval-id>
  clawix approvals deny <approval-id>
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
    case 'approve':
      return approve(rest);
    case 'deny':
      return deny(rest);
    default:
      throw new Error(`unknown subcommand "${sub}". Run \`clawix approvals --help\`.`);
  }
}

async function ls(args, { json }) {
  const homeId = parseFlag(args, '--home');
  const path = homeId ? `/v1/homes/${encodeURIComponent(homeId)}/approvals` : '/v1/approvals';
  const response = await call('GET', path);
  let approvals = response.approvals || [];
  if (hasFlag(args, '--pending')) {
    approvals = approvals.filter((a) => a.status === 'pending');
  }
  if (json) {
    printJSON({ approvals });
    return;
  }
  printTable(
    ['id', 'status', 'action', 'reason', 'createdAt'],
    approvals.map((approval) => [
      approval.id,
      approval.status,
      approval.action?.action || '—',
      approval.reason,
      approval.createdAt,
    ]),
  );
}

async function approve(args) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error('clawix approvals approve <approval-id>');
  const response = await call('POST', `/v1/approvals/${encodeURIComponent(id)}/approve`);
  process.stdout.write(`approved: ${id} · ${response.result?.status || 'unknown'}\n`);
}

async function deny(args) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error('clawix approvals deny <approval-id>');
  await call('POST', `/v1/approvals/${encodeURIComponent(id)}/deny`);
  process.stdout.write(`denied: ${id}\n`);
}

module.exports = { run };
