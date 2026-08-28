const fs = require('fs');
const path = require('path');

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

const publicDir = path.resolve(__dirname, '..', 'public');
const files = fs.readdirSync(publicDir).filter((f) => f.endsWith('.html'));

console.log(`\nExternal dependency delivery tests (${files.length} pages)\n`);

function extractTags(html) {
    const tags = [];
    const tagRe = /<(script|link)\b([^>]*)>/gi;
    let m;
    while ((m = tagRe.exec(html))) {
        const [, tagName, attrsRaw] = m;
        const srcMatch = attrsRaw.match(/\bsrc\s*=\s*["']([^"']+)["']/i);
        const hrefMatch = attrsRaw.match(/\bhref\s*=\s*["']([^"']+)["']/i);
        const relMatch = attrsRaw.match(/\brel\s*=\s*["']([^"']+)["']/i);
        const isDefer = /\bdefer\b/i.test(attrsRaw);
        const isAsync = /\basync\b/i.test(attrsRaw);
        tags.push({
            tagName: tagName.toLowerCase(),
            src: srcMatch ? srcMatch[1] : null,
            href: hrefMatch ? hrefMatch[1] : null,
            rel: relMatch ? relMatch[1] : null,
            defer: isDefer,
            async: isAsync,
            index: m.index
        });
    }
    return tags;
}

function isExternal(url) {
    return /^https?:\/\//i.test(url);
}

for (const file of files) {
    const html = fs.readFileSync(path.join(publicDir, file), 'utf8');
    const tags = extractTags(html);
    const scripts = tags.filter((t) => t.tagName === 'script' && t.src);
    const stylesheets = tags.filter((t) => t.tagName === 'link' && t.rel && /stylesheet/i.test(t.rel) && t.href);

    console.log(`${file}`);

const authGate = scripts.find((s) => /auth-gate\.js$/i.test(s.src));
    if (authGate) {
        check('auth-gate.js is not defer/async', !authGate.defer && !authGate.async, authGate.src);
    }

const redirectGuard = scripts.find((s) => /redirect-guard\.js$/i.test(s.src));
    if (redirectGuard) {
        check('redirect-guard.js is not defer/async', !redirectGuard.defer && !redirectGuard.async, redirectGuard.src);
    }

const externalScriptUrls = scripts.filter((s) => isExternal(s.src)).map((s) => s.src);
    const dupScripts = externalScriptUrls.filter((u, i) => externalScriptUrls.indexOf(u) !== i);
    check('no duplicate external script URL', dupScripts.length === 0, dupScripts.join(', '));

const externalStyleUrls = stylesheets.filter((s) => isExternal(s.href)).map((s) => s.href);
    const dupStyles = externalStyleUrls.filter((u, i) => externalStyleUrls.indexOf(u) !== i);
    check('no duplicate external stylesheet URL', dupStyles.length === 0, dupStyles.join(', '));

const chartIdx = scripts.findIndex((s) => /chart(\.umd)?(\.min)?\.js/i.test(s.src));
    if (chartIdx !== -1) {
        const consumer = scripts.findIndex((s, i) => i > chartIdx && /(analytics|feedback-dashboard)\.js$/i.test(s.src));
        check('Chart.js loads before its local consumer', consumer === -1 || consumer > chartIdx);
    }

const leafletIdx = scripts.findIndex((s) => /\bleaflet@[\d.]+\/dist\/leaflet\.js/i.test(s.src));
    const clusterIdx = scripts.findIndex((s) => /leaflet\.markercluster\.js/i.test(s.src));
    if (clusterIdx !== -1) {
        check('MarkerCluster appears after Leaflet', leafletIdx !== -1 && clusterIdx > leafletIdx);
    }
    if (leafletIdx !== -1) {
        const mapConsumerIdx = scripts.findIndex((s, i) => i > leafletIdx && /(map|mini-map|clinic|doctor|find-clinics)\.js$/i.test(s.src));
        check('Leaflet loads before its local map consumer', mapConsumerIdx === -1 || mapConsumerIdx > leafletIdx);
        if (clusterIdx !== -1 && mapConsumerIdx !== -1) {
            check('local consumer loads after MarkerCluster', mapConsumerIdx > clusterIdx);
        }
    }

const socketIdx = scripts.findIndex((s) => /socket\.io.*\.js/i.test(s.src));
    if (socketIdx !== -1) {
        const dmIdx = scripts.findIndex((s, i) => i > socketIdx && /direct-messages\.js$/i.test(s.src));
        check('Socket.IO client loads before direct-messages.js', dmIdx === -1 || dmIdx > socketIdx);
    }

const staticGis = scripts.some((s) => /accounts\.google\.com\/gsi\/client/i.test(s.src));
    check('no static Google Identity <script> tag (loaded dynamically)', !staticGis);

const fontLinks = stylesheets.filter((s) => /fonts\.googleapis\.com\/css2/i.test(s.href));
    for (const link of fontLinks) {
        check('Google Fonts link has display=swap', /display=swap/i.test(link.href));
    }

const httpUrls = tags.filter((t) => (t.src && /^http:\/\//i.test(t.src)) || (t.href && /^http:\/\//i.test(t.href)));
    check('no plain-http external dependency URLs', httpUrls.length === 0, JSON.stringify(httpUrls));

const faCss = stylesheets.filter((s) => /font-awesome\/[\d.]+\/css\/all(\.min)?\.css/i.test(s.href));
    const faJs = scripts.filter((s) => /font-awesome\/[\d.]+\/js\/all(\.min)?\.js/i.test(s.src));
    check('Font Awesome CSS kit not loaded more than once', faCss.length <= 1);
    check('Font Awesome JS kit not loaded more than once', faJs.length <= 1);
    check('Font Awesome CSS and JS kit are not both loaded on the same page', !(faCss.length === 1 && faJs.length === 1),
        'redundant duplicate icon delivery mechanism');

const allowedHosts = [
        'fonts.googleapis.com',
        'fonts.gstatic.com',
        'cdnjs.cloudflare.com',
        'cdn.jsdelivr.net',
        'unpkg.com',
        'accounts.google.com',
        'tile.openstreetmap.org'
    ];
    const externalUrls = [...externalScriptUrls, ...externalStyleUrls];
    const unknownHosts = externalUrls
        .map((u) => {
            try { return new URL(u).host; } catch { return u; }
        })
        .filter((host) => !allowedHosts.includes(host));
    check('no unrecognized external host introduced', unknownHosts.length === 0, unknownHosts.join(', '));

const deferredExternal = scripts.filter((s) => isExternal(s.src) && s.defer);
    check('no external dependency uses defer in this slice (ordering left as classic, in-order scripts)',
        deferredExternal.length === 0, deferredExternal.map((s) => s.src).join(', '));

    console.log('');
}

console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);
