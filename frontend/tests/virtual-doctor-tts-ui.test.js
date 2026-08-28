const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { performance } = require('perf_hooks');

let passed = 0;
let failed = 0;
function check(name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  PASS ${name}`);
    } else {
        failed += 1;
        console.error(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`);
    }
}

const source = fs.readFileSync(
    path.resolve(__dirname, '..', 'src/js/virtual-doctor-tts.js'),
    'utf8'
);

class FakeAudio {
    constructor() {
        this.listeners = {};
        this.src = '';
        this.currentTime = 0;
        this.preload = '';
    }
    addEventListener(type, fn) {
        (this.listeners[type] = this.listeners[type] || []).push(fn);
    }
    removeEventListener(type, fn) {
        if (this.listeners[type]) this.listeners[type] = this.listeners[type].filter((f) => f !== fn);
    }
    play() {
        setTimeout(() => (this.listeners.ended || []).slice().forEach((fn) => fn()), 0);
        return Promise.resolve();
    }
    pause() {}
}

function loadTts({ sessionId, fetchImpl }) {
    const fetchCalls = [];
    const sandbox = {
        console,
        Promise,
        Map,
        Set,
        JSON,
        AbortController,
        performance,
        setTimeout,
        clearTimeout,
        setInterval,
        clearInterval,
        Audio: FakeAudio,
        URL: {
            createObjectURL: () => 'blob:fake-url-' + fetchCalls.length,
            revokeObjectURL: () => {}
        },
        API: {
            getOrigin: () => 'http://127.0.0.1:3001',
            getAccessToken: () => 'test-access-token'
        },
        VirtualDoctorSession: sessionId === undefined
            ? undefined
            : { getSessionId: () => sessionId },
        fetch: async (url, opts) => {
            fetchCalls.push({ url, opts });
            return fetchImpl ? fetchImpl(url, opts) : {
                ok: true,
                headers: { get: () => null },
                blob: async () => ({ size: 4, type: 'audio/wav' })
            };
        }
    };
    sandbox.globalThis = sandbox;
    vm.createContext(sandbox);
    const mod = vm.runInContext(source + '\n;VirtualDoctorTTS;', sandbox, { filename: 'virtual-doctor-tts.js' });
    return { mod, fetchCalls };
}

(async () => {

    {
        const { mod, fetchCalls } = loadTts({ sessionId: 'session-abc123' });

        let result;
        let threw = null;
        try {
            result = await mod.speak('Hello there. How are you today?', 'en', {});
        } catch (err) {
            threw = err;
        }

        check('speak() does not throw ReferenceError: cfg is not defined', threw === null, threw && threw.message);
        check('speak() resolves ok:true with an active session', !!result && result.ok === true, JSON.stringify(result));
        check('a real request reached /api/virtual-doctor/speak', fetchCalls.length > 0);
        check(
            'every request carries the active session_id from VirtualDoctorSession',
            fetchCalls.length > 0 && fetchCalls.every((c) => JSON.parse(c.opts.body).session_id === 'session-abc123')
        );
        check(
            'every request is authenticated with the bearer token',
            fetchCalls.length > 0 && fetchCalls.every((c) => c.opts.headers.Authorization === 'Bearer test-access-token')
        );
        check(
            'requests target the backend gateway, not the AI service directly',
            fetchCalls.every((c) => c.url === 'http://127.0.0.1:3001/api/virtual-doctor/speak')
        );
    }

{
        const { mod, fetchCalls } = loadTts({ sessionId: null });
        let threw = null;
        let result;
        try {
            result = await mod.speak('No session yet.', 'en', {});
        } catch (err) {
            threw = err;
        }
        check('speak() does not throw when VirtualDoctorSession has no active session', threw === null, threw && threw.message);
        check('session_id is sent as null rather than crashing', fetchCalls.length > 0 && JSON.parse(fetchCalls[0].opts.body).session_id === null);
        check('result is still ok:true', !!result && result.ok === true, JSON.stringify(result));
    }

{
        const { mod } = loadTts({ sessionId: undefined });
        let threw = null;
        try {
            await mod.speak('Still safe.', 'en', {});
        } catch (err) {
            threw = err;
        }
        check('speak() does not throw when VirtualDoctorSession is undefined', threw === null, threw && threw.message);
    }

    console.log(`\nVirtual Doctor TTS regression: ${passed} passed, ${failed} failed`);
    process.exitCode = failed ? 1 : 0;
})().catch((err) => {
    console.error('Unhandled error in virtual-doctor-tts-ui.test.js:', err);
    process.exitCode = 1;
});
