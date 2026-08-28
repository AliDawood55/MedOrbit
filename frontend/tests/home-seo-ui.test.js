'use strict';

const fs = require('fs');
const path = require('path');

const PUBLIC_DIR = path.join(__dirname, '..', 'public');
const NGINX_CONF = path.join(__dirname, '..', 'nginx.conf');
const FAVICON = path.join(PUBLIC_DIR, 'favicon.svg');

let failures = 0;

function assert(condition, message) {
    if (!condition) {
        failures++;
        console.error(`FAIL: ${message}`);
    } else {
        console.log(`PASS: ${message}`);
    }
}

const nginxConf = fs.readFileSync(NGINX_CONF, 'utf8');
const homeHtml = fs.readFileSync(path.join(PUBLIC_DIR, 'home.html'), 'utf8');
const htmlFiles = fs.readdirSync(PUBLIC_DIR).filter((f) => f.endsWith('.html'));

const indexEntries = [...nginxConf.matchAll(/\/public\/([\w.-]+\.html)\s+"index, follow"/g)].map((m) => m[1]);
assert(indexEntries.length === 1 && indexEntries[0] === 'home.html', 'home.html is the unique "index, follow" entry in nginx.conf');

const rootBlockMatch = nginxConf.match(/location\s*=\s*\/\s*\{([^}]*)\}/);
assert(!!rootBlockMatch, 'nginx.conf has a location = / block');
const rootBlock = rootBlockMatch ? rootBlockMatch[1] : '';
assert(/return\s+\d+\s+\/public\/home\.html\s*;/.test(rootBlock), 'bare-root redirect target is /public/home.html');
assert(!/return\s+\d+\s+\/public\/index\.html\s*;/.test(rootBlock), 'bare-root redirect no longer targets /public/index.html');

function hasTag(html, regex) {
    return regex.test(html);
}

const titleMatch = homeHtml.match(/<title>([^<]*)<\/title>/);
assert(!!titleMatch && titleMatch[1].trim().length > 0, 'home.html has a non-empty <title>');

const descMatch = homeHtml.match(/<meta\s+name=["']description["']\s+content=["']([^"']*)["']/);
assert(!!descMatch && descMatch[1].trim().length > 0, 'home.html has a non-empty meta description');

assert(hasTag(homeHtml, /<meta\s+name=["']theme-color["']/), 'home.html has theme-color meta');
assert(hasTag(homeHtml, /<meta\s+property=["']og:type["']\s+content=["']website["']/), 'home.html has og:type');
assert(hasTag(homeHtml, /<meta\s+property=["']og:site_name["']\s+content=["'][^"']+["']/), 'home.html has og:site_name');
assert(hasTag(homeHtml, /<meta\s+property=["']og:title["']\s+content=["'][^"']+["']/), 'home.html has og:title');
assert(hasTag(homeHtml, /<meta\s+property=["']og:description["']\s+content=["'][^"']+["']/), 'home.html has og:description');
assert(hasTag(homeHtml, /<meta\s+name=["']twitter:card["']\s+content=["'][^"']+["']/), 'home.html has twitter:card');
assert(hasTag(homeHtml, /<meta\s+name=["']twitter:title["']\s+content=["'][^"']+["']/), 'home.html has twitter:title');
assert(hasTag(homeHtml, /<meta\s+name=["']twitter:description["']\s+content=["'][^"']+["']/), 'home.html has twitter:description');

const bannedPatterns = [/localhost/i, /127\.0\.0\.1/, /medorbit\.(com|ps|io|app)/i, /example\.com/i];
const socialMetaBlockMatches = homeHtml.match(/<meta\s+(?:property|name)=["'](?:og:|twitter:)[^"']*["'][^>]*>/g) || [];
for (const tag of socialMetaBlockMatches) {
    for (const pattern of bannedPatterns) {
        assert(!pattern.test(tag), `home.html social meta tag has no fabricated domain: ${tag}`);
    }
}

const canonicalMatch = homeHtml.match(/<link\s+rel=["']canonical["']\s+href=["']([^"']*)["']/);
if (canonicalMatch) {
    const href = canonicalMatch[1];
    for (const pattern of bannedPatterns) {
        assert(!pattern.test(href), `canonical href does not use a fabricated/placeholder domain: ${href}`);
    }
} else {
    console.log('INFO: canonical link deferred (no confirmed production origin) — acceptable per spec');
}

const ogUrlMatch = homeHtml.match(/<meta\s+property=["']og:url["']\s+content=["']([^"']*)["']/);
if (ogUrlMatch) {
    const content = ogUrlMatch[1];
    for (const pattern of bannedPatterns) {
        assert(!pattern.test(content), `og:url does not use a fabricated/placeholder domain: ${content}`);
    }
} else {
    console.log('INFO: og:url deferred (no confirmed production origin) — acceptable per spec');
}

for (const file of htmlFiles) {
    const html = fs.readFileSync(path.join(PUBLIC_DIR, file), 'utf8');
    const matches = html.match(/<link\s+rel=["']icon["'][^>]*href=["']favicon\.svg["'][^>]*>/g) || [];
    assert(matches.length === 1, `${file} has exactly one favicon link (found ${matches.length})`);
}

assert(fs.existsSync(FAVICON), 'frontend/public/favicon.svg exists');
if (fs.existsSync(FAVICON)) {
    const svgContent = fs.readFileSync(FAVICON, 'utf8');
    assert(/<svg[\s>]/.test(svgContent) && /<\/svg>/.test(svgContent), 'favicon.svg contains a valid <svg> root element');
    const withoutNamespaceDecls = svgContent.replace(/xmlns(?::\w+)?=["']https?:\/\/[^"']*["']/gi, '');
    assert(!/https?:\/\//i.test(withoutNamespaceDecls), 'favicon.svg contains no external http/https resource references (xmlns namespace URIs excluded)');
}

const protectedFiles = htmlFiles.filter((f) => f !== 'home.html');
for (const file of protectedFiles) {
    const uri = `/public/${file}`;
    const regex = new RegExp(`${uri.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s+"index, follow"`);
    assert(!regex.test(nginxConf), `${file} is not marked "index, follow" in nginx.conf`);
}

if (failures > 0) {
    console.error(`\n${failures} assertion(s) failed.`);
    process.exit(1);
} else {
    console.log('\nAll assertions passed.');
    process.exit(0);
}
