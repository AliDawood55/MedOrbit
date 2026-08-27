'use strict';

const fs = require('fs');
const path = require('path');

const NGINX_CONF = path.join(__dirname, '..', 'nginx.conf');

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

// 1. gzip is enabled
assert(/gzip\s+on\s*;/.test(nginxConf), 'gzip is enabled');

// 2. gzip_vary is enabled
assert(/gzip_vary\s+on\s*;/.test(nginxConf), 'gzip_vary is enabled');

// 3. gzip_min_length is configured
const minLengthMatch = nginxConf.match(/gzip_min_length\s+(\d+)\s*;/);
assert(!!minLengthMatch, 'gzip_min_length is configured');
if (minLengthMatch) {
    assert(Number(minLengthMatch[1]) > 0, 'gzip_min_length is a positive value');
}

// 4. gzip compression level is sane (not an unnecessarily expensive maximum)
const compLevelMatch = nginxConf.match(/gzip_comp_level\s+(\d+)\s*;/);
assert(!!compLevelMatch, 'gzip_comp_level is configured');
if (compLevelMatch) {
    const level = Number(compLevelMatch[1]);
    assert(level >= 1 && level <= 6, `gzip_comp_level (${level}) is a moderate value, not maxed out at 9`);
}

// Extract the gzip_types block for the MIME assertions below.
const gzipTypesMatch = nginxConf.match(/gzip_types\s+([^;]*);/);
assert(!!gzipTypesMatch, 'gzip_types block is present');
const gzipTypesBlock = gzipTypesMatch ? gzipTypesMatch[1] : '';

// 5. CSS is included in compressible MIME types
assert(/text\/css/.test(gzipTypesBlock), 'gzip_types includes text/css');

// 6. JavaScript is included
assert(/application\/javascript/.test(gzipTypesBlock), 'gzip_types includes application/javascript');

// 7. JSON is included
assert(/application\/json/.test(gzipTypesBlock), 'gzip_types includes application/json');

// 8. SVG is included
assert(/image\/svg\+xml/.test(gzipTypesBlock), 'gzip_types includes image/svg+xml');

// 9. already-compressed raster/font formats are NOT explicitly added to gzip_types
const excludedTypes = [
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
    'font/woff',
    'font/woff2',
    'application/font-woff',
    'application/font-woff2',
    'application/zip',
];
for (const type of excludedTypes) {
    assert(!gzipTypesBlock.includes(type), `gzip_types does not include already-compressed type: ${type}`);
}

// 10. HTML/JS/CSS still retain Cache-Control: no-cache behavior
const htmlJsCssBlockMatch = nginxConf.match(/location\s+~\*\s+\\\.\(\?:html\|js\|css\)\$\s*\{([^]*?)\n {4}\}/);
assert(!!htmlJsCssBlockMatch, 'nginx.conf has the html|js|css location block');
const htmlJsCssBlock = htmlJsCssBlockMatch ? htmlJsCssBlockMatch[1] : '';
assert(/Cache-Control\s+"no-cache"/.test(htmlJsCssBlock), 'html|js|css location sends Cache-Control: no-cache');

// 11. no immutable/one-year caching was added to mutable JS/CSS
assert(!/immutable/i.test(nginxConf), 'nginx.conf does not use immutable caching');
assert(!/max-age=31536000/.test(nginxConf), 'nginx.conf does not use one-year max-age caching');

// 12. P5B2 X-Robots policy remains intact
assert(/map\s+\$uri\s+\$medorbit_robots\s*\{/.test(nginxConf), 'X-Robots-Tag $medorbit_robots map is intact');
assert(/\/public\/home\.html\s+"index, follow"/.test(nginxConf), 'home.html is still marked index, follow');
assert(/add_header\s+X-Robots-Tag\s+\$medorbit_robots\s+always\s*;/.test(nginxConf), 'X-Robots-Tag header is still emitted');

// 13. P5E2 root redirect remains: /public/home.html
const rootBlockMatch = nginxConf.match(/location\s*=\s*\/\s*\{([^}]*)\}/);
assert(!!rootBlockMatch, 'nginx.conf has a location = / block');
const rootBlock = rootBlockMatch ? rootBlockMatch[1] : '';
assert(/return\s+\d+\s+\/public\/home\.html\s*;/.test(rootBlock), 'bare-root redirect target is /public/home.html');

// 14. security headers remain present
assert(/add_header\s+Content-Security-Policy\s+"/.test(nginxConf), 'Content-Security-Policy header is present');
assert(/add_header\s+Permissions-Policy\s+"/.test(nginxConf), 'Permissions-Policy header is present');
assert(/add_header\s+Referrer-Policy\s+"strict-origin-when-cross-origin"/.test(nginxConf), 'Referrer-Policy header is present');
assert(/add_header\s+X-Content-Type-Options\s+"nosniff"/.test(nginxConf), 'X-Content-Type-Options header is present');

if (failures > 0) {
    console.error(`\n${failures} assertion(s) failed.`);
    process.exit(1);
} else {
    console.log('\nAll assertions passed.');
    process.exit(0);
}
