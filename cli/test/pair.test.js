'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { publicPairingPayload } = require('../lib/pair');

test('publicPairingPayload uses hostDisplayName in the v1 pairing contract', () => {
    const payload = publicPairingPayload({
        v: 1,
        host: '192.168.1.10',
        port: 24080,
        token: 'bearer-token',
        hostDisplayName: 'Studio Mac',
        shortCode: 'ABC-DEF-GHJ',
        tailscaleHost: '100.64.0.10'
    });

    assert.deepEqual(payload, {
        v: 1,
        host: '192.168.1.10',
        port: 24080,
        token: 'bearer-token',
        hostDisplayName: 'Studio Mac',
        shortCode: 'ABC-DEF-GHJ',
        tailscaleHost: '100.64.0.10'
    });
    assert.equal(Object.hasOwn(payload, 'macName'), false);
});

test('publicPairingPayload omits shortCode from QR payloads', () => {
    const payload = publicPairingPayload({
        v: 1,
        host: '192.168.1.10',
        port: 24080,
        token: 'bearer-token',
        hostDisplayName: 'Studio Mac',
        shortCode: 'ABC-DEF-GHJ',
        tailscaleHost: null
    }, { includeShortCode: false });

    assert.deepEqual(payload, {
        v: 1,
        host: '192.168.1.10',
        port: 24080,
        token: 'bearer-token',
        hostDisplayName: 'Studio Mac'
    });
});
