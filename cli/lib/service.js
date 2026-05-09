'use strict';

const { IS_LINUX } = require('./platform');

module.exports = IS_LINUX ? require('./systemctl') : require('./launchctl');
