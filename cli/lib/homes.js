'use strict';

const { call, printJSON, printTable, hasFlag } = require('./iot-client');

const HELP = `\
clawix homes — list the user's homes

usage
  clawix homes ls [--json]
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
      return ls({ json });
    default:
      throw new Error(`unknown subcommand "${sub}". Run \`clawix homes --help\`.`);
  }
}

async function ls({ json }) {
  const response = await call('GET', '/v1/homes');
  const homes = response.homes || [];
  if (json) {
    printJSON({ homes });
    return;
  }
  printTable(
    ['id', 'label', 'default', 'createdAt'],
    homes.map((home) => [home.id, home.label, home.isDefault ? 'yes' : 'no', home.createdAt]),
  );
}

module.exports = { run };
