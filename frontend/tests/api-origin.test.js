const fs = require('fs');
const path = require('path');
const vm = require('vm');

let passed = 0;
let failed = 0;

function check(name, condition) {
    if (condition) {
        passed += 1;
        console.log(`  ✓ ${name}`);
    } else {
        failed += 1;
        console.error(`  ✗ ${name}`);
    }
}

function loadApi({ protocol, hostname, origin, override } = {}) {
    const store = new Map();
    const location = {
        protocol: protocol || 'http:',
        hostname: hostname || 'localhost',
        origin: origin || `${protocol || 'http:'}//${hostname || 'localhost'}`,
    };
    const sandbox = {
        window: {
            location,
            MEDORBIT_API_URL: override,
            dispatchEvent() {},
        },
        localStorage: {
            getItem: (key) => store.get(key) || null,
            setItem: (key, value) => store.set(key, String(value)),
            removeItem: (key) => store.delete(key),
        },
        CustomEvent: function CustomEvent(type) { return { type }; },
        fetch: async () => ({ ok: true, status: 200, headers: { get: () => null }, json: async () => ({}) }),
        URL,
        URLSearchParams,
        FormData: function FormData() {},
        Map,
        Promise,
        console,
    };
    sandbox.globalThis = sandbox;
    const source = fs.readFileSync(path.resolve(__dirname, '..', 'src/js/api.js'), 'utf8');
    vm.createContext(sandbox);
    return vm.runInContext(`${source}\n;API;`, sandbox, { filename: 'api.js' });
}

console.log('\nFrontend API origin tests\n');

const stagingApi = loadApi({
    protocol: 'https:',
    hostname: 'staging.medorbit.example',
    origin: 'https://staging.medorbit.example',
});
check('HTTPS deployment uses Caddy same-origin API', stagingApi.getOrigin() === 'https://staging.medorbit.example');

const localApi = loadApi({
    protocol: 'http:',
    hostname: 'localhost',
    origin: 'http://localhost:8080',
});
check('HTTP local development keeps backend port 3001', localApi.getOrigin() === 'http://localhost:3001');

const overriddenApi = loadApi({
    protocol: 'https:',
    hostname: 'staging.medorbit.example',
    origin: 'https://staging.medorbit.example',
    override: 'https://api.example.test/api/',
});
check('explicit API override remains authoritative', overriddenApi.getOrigin() === 'https://api.example.test');

console.log(`\nFrontend API origin tests: ${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
