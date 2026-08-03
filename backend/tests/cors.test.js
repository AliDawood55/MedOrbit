// backend/tests/cors.test.js
// Run: node backend/tests/cors.test.js

const { isAllowedCorsOrigin, isPrivateNetworkHost } = require('../src/config/cors');

let passed = 0;
let failed = 0;

function assert(name, condition) {
    if (condition) {
        passed++;
        console.log(`  ok ${name}`);
    } else {
        failed++;
        console.log(`  fail ${name}`);
    }
}

const lockedCors = {
    corsOrigin: 'http://localhost:8080,http://127.0.0.1:8080',
    frontendPort: '8080'
};

assert('allows configured localhost origin',
    isAllowedCorsOrigin('http://localhost:8080', lockedCors));

assert('allows configured loopback origin',
    isAllowedCorsOrigin('http://127.0.0.1:8080', lockedCors));

assert('allows 192.168 LAN frontend origin',
    isAllowedCorsOrigin('http://192.168.233.1:8080', lockedCors));

assert('allows 10.x LAN frontend origin',
    isAllowedCorsOrigin('http://10.0.0.25:8080', lockedCors));

assert('allows 172.16-31 LAN frontend origin',
    isAllowedCorsOrigin('http://172.20.0.8:8080', lockedCors));

assert('blocks LAN frontend origin on the wrong port',
    !isAllowedCorsOrigin('http://192.168.233.1:5173', lockedCors));

assert('blocks public network origins not explicitly configured',
    !isAllowedCorsOrigin('http://8.8.8.8:8080', lockedCors));

assert('recognizes localhost as private',
    isPrivateNetworkHost('localhost'));

assert('does not treat public hostnames as private',
    !isPrivateNetworkHost('example.com'));

console.log(`\nCORS tests: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
