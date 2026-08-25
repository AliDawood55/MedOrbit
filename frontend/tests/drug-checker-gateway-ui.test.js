const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.resolve(__dirname, '../src/js/drug-checker.js'), 'utf8');
const apiSource = fs.readFileSync(path.resolve(__dirname, '../src/js/api.js'), 'utf8');
const nginxSource = fs.readFileSync(path.resolve(__dirname, '../nginx.conf'), 'utf8');

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

console.log('\nDrug Checker backend gateway tests\n');
check('uses the authenticated backend drug-interactions route',
    /API\.post\('\/ai\/drug-interactions',\s*\{\s*medication_names:\s*medications\s*\}\)/s.test(source));
check('unwraps the standard backend response envelope for the existing renderer',
    /showResult\(response\?\.data \|\| response\)/.test(source));
check('contains no direct fetch or AI-origin helper',
    !/\bfetch\s*\(|getAiOrigin|AI_BASE|8001/.test(source));
check('shared browser API exposes no direct AI-service origin helper',
    !/function getAiOrigin\s*\(/.test(apiSource) && !/\bgetAiOrigin\b/.test(apiSource.slice(apiSource.indexOf('return {'))));
check('browser CSP no longer permits direct AI port access', !/8001/.test(nginxSource));

console.log(`\nDrug Checker backend gateway: ${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
