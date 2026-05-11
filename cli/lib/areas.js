'use strict';

const { call, printJSON, printTable, parseFlag, hasFlag } = require('./iot-client');

const HELP = `\
clawix areas — list rooms / zones

usage
  clawix areas ls [--home <id>] [--json]
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
    default:
      throw new Error(`unknown subcommand "${sub}". Run \`clawix areas --help\`.`);
  }
}

async function ls(args, { json }) {
  const homeId = parseFlag(args, '--home');
  const path = homeId ? `/v1/homes/${encodeURIComponent(homeId)}/areas` : '/v1/areas';
  const response = await call('GET', path);
  const areas = response.areas || [];
  if (json) {
    printJSON({ areas });
    return;
  }
  printTable(
    ['id', 'label', 'home', 'aliases'],
    areas.map((area) => [area.id, area.label, area.homeId, (area.aliases || []).join(',')]),
  );
}

module.exports = { run };
