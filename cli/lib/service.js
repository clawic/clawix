'use strict';

// Per-platform service manager facade. The CLI talks to `service`
// instead of importing `launchctl` or `systemctl` directly, so the same
// command files (daemon.js, up.js, install-app.js) work on macOS, Linux,
// and Windows without if/else branches at every call site.

const { IS_LINUX, IS_WINDOWS } = require('./platform');

let backend;
if (IS_LINUX) {
  backend = require('./systemctl');
} else if (IS_WINDOWS) {
  // The Windows build registers the daemon via the Run registry key and
  // the Task Scheduler. Implementation is in the Windows fork.
  try {
    backend = require('./taskscheduler');
  } catch (_) {
    backend = require('./launchctl'); // fallback that errors loudly
  }
} else {
  backend = require('./launchctl');
}

module.exports = backend;
