const fs = require('fs');
const path = require('path');
const vm = require('vm');

let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  ✓ ${name}`);
    } else {
        failed += 1;
        console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
    }
}

function frontendPath(relativePath) {
    return path.resolve(__dirname, '..', relativePath);
}

function frontendFile(relativePath) {
    return fs.readFileSync(frontendPath(relativePath), 'utf8');
}

console.log('\nGlobal Toast tests\n');

function element(tag = 'div') {
    const el = {
        tagName: tag,
        style: {},
        attributes: {},
        children: [],
        parentNode: null,
        setAttribute(k, v) { this.attributes[k] = String(v); },
        getAttribute(k) { return k in this.attributes ? this.attributes[k] : null; },
        removeAttribute(k) { delete this.attributes[k]; },
        hasAttribute(k) { return k in this.attributes; },
        appendChild(child) { child.parentNode = el; this.children.push(child); return child; },
        remove() {
            if (this.parentNode) {
                const i = this.parentNode.children.indexOf(this);
                if (i !== -1) this.parentNode.children.splice(i, 1);
            }
        },
        set className(v) { this._className = v; },
        get className() { return this._className || ''; },
        set innerHTML(v) { this._html = v; this.children = []; },
        get innerHTML() { return this._html; },
        set textContent(v) { this._text = v; this.children = []; this._html = undefined; },
        get textContent() { return this._text; }
    };
    return el;
}

function loadToast() {
    const container = element('div');
    container.id = 'toastContainer';

    const sandbox = {
        console,
        setTimeout,
        clearTimeout,
        document: {
            getElementById: (id) => (id === 'toastContainer' ? container : null),
            createElement: (tag) => element(tag)
        }
    };
    sandbox.globalThis = sandbox;

    const source = frontendFile('src/js/toast.js');
    vm.createContext(sandbox);
    const ToastModule = vm.runInContext(source + '\n;Toast;', sandbox, { filename: 'toast.js' });
    return { Toast: ToastModule, container };
}

let Toast, container;
try {
    ({ Toast, container } = loadToast());
    check('toast.js boots in a minimal DOM stub', !!Toast);
} catch (err) {
    check('toast.js boots in a minimal DOM stub', false, err.message);
    process.exit(1);
}

const PAYLOAD = '<img src=x onerror=alert(1)>';

Toast.error(PAYLOAD, 10000);
const errorToast = container.children[container.children.length - 1];
const errorText = errorToast.children.find((c) => c.tagName === 'span');

check('the payload is rendered as literal text, not parsed HTML',
    errorText.textContent === PAYLOAD, JSON.stringify(errorText.textContent));
check('the message span has no HTML children (no img element was created)',
    errorText.children.length === 0);
check('the message is set via textContent, not innerHTML',
    errorText._html === undefined);

check('error toasts mark the container as an assertive alert',
    container.getAttribute('role') === 'alert' && container.getAttribute('aria-live') === 'assertive');

Toast.success('Saved successfully', 10000);
check('a later success toast relaxes the container to a polite status region',
    container.getAttribute('role') === 'status' && container.getAttribute('aria-live') === 'polite');

const successToast = container.children[container.children.length - 1];
check('individual toasts carry no live-region role of their own (single announcement owner)',
    !successToast.hasAttribute('role') && !successToast.hasAttribute('aria-live'));

Toast.warning('Careful', 10000);
check('warning toasts are treated as urgent, same as error',
    container.getAttribute('role') === 'alert' && container.getAttribute('aria-live') === 'assertive');

Toast.info('FYI', 10000);
check('info toasts are treated as polite, same as success',
    container.getAttribute('role') === 'status' && container.getAttribute('aria-live') === 'polite');

const infoToast = container.children[container.children.length - 1];
const infoIcon = infoToast.children.find((c) => c.tagName === 'i');
check('the icon is hidden from assistive tech',
    infoIcon.getAttribute('aria-hidden') === 'true');
check('the icon carries the expected fontawesome class',
    infoIcon.className.includes('fa-info-circle'));

['success', 'error', 'warning', 'info'].forEach((type) => {
    Toast[type](`${type} message`, 10000);
    const toast = container.children[container.children.length - 1];
    check(`Toast.${type} delegates with the "${type}" class`,
        toast.className === `toast ${type}`);
});

const before = container.children.length;
Toast.info('Will disappear', 5);
const during = container.children.length;
check('a new toast is appended to the container', during === before + 1);

setTimeout(() => {
    const after = container.children.length;
    check('the toast removes itself from the container after its duration elapses',
        after === before);

    console.log(`\n${passed} passed, ${failed} failed\n`);
    process.exit(failed === 0 ? 0 : 1);
}, 400);
