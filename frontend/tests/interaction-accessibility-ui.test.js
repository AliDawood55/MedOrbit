'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const CSS_DIR = path.join(__dirname, '..', 'src', 'css');

function read(file) {
    return fs.readFileSync(path.join(CSS_DIR, file), 'utf8');
}

function extractBlock(css, selectorPattern) {
    const re = new RegExp(selectorPattern.source + '\\s*\\{([^}]*)\\}', 'g');
    const match = re.exec(css);
    return match ? match[1] : null;
}

function extractAllBlocks(css, selectorPattern) {
    const re = new RegExp(selectorPattern.source + '\\s*\\{([^}]*)\\}', 'g');
    const blocks = [];
    let match;
    while ((match = re.exec(css)) !== null) {
        blocks.push(match[1]);
    }
    return blocks;
}

function extractAllMediaBlocks(css, mediaPattern) {
    const re = new RegExp(mediaPattern.source, 'g');
    const blocks = [];
    let m;
    while ((m = re.exec(css)) !== null) {
        let start = m.index + m[0].length;
        let depth = 1;
        let i = start;
        while (i < css.length && depth > 0) {
            if (css[i] === '{') depth++;
            else if (css[i] === '}') depth--;
            i++;
        }
        blocks.push(css.slice(start, i - 1));
    }
    return blocks;
}

function extractMediaBlock(css, mediaPattern) {
    const startMatch = css.match(mediaPattern);
    if (!startMatch) return null;
    let start = startMatch.index + startMatch[0].length;
    let depth = 1;
    let i = start;
    while (i < css.length && depth > 0) {
        if (css[i] === '{') depth++;
        else if (css[i] === '}') depth--;
        i++;
    }
    return css.slice(start, i - 1);
}

let passCount = 0;
function test(name, fn) {
    try {
        fn();
        passCount++;
        console.log(`  ok - ${name}`);
    } catch (err) {
        console.error(`  FAIL - ${name}`);
        console.error(`    ${err.message}`);
        process.exitCode = 1;
    }
}

console.log('interaction-accessibility-ui');

// 1. Shared prefers-reduced-motion rule exists in main.css
test('main.css defines a shared prefers-reduced-motion baseline', () => {
    const css = read('main.css');
    assert.ok(/@media\s*\(prefers-reduced-motion:\s*reduce\)/.test(css));
    const block = extractMediaBlock(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{/);
    assert.ok(block, 'reduced-motion media block should be found');
    assert.ok(/\.loader-logo/.test(block), 'loader logo motion should be addressed');
    assert.ok(/\.loader-bar-fill/.test(block), 'loader bar motion should be addressed');
    assert.ok(/\.toast\b/.test(block), 'toast entrance motion should be addressed');
});

// 2. Spinner/loading reduced-motion coverage exists
test('components.css stops spinner animation under reduced motion, without removing the element', () => {
    const css = read('components.css');
    const blocks = extractAllMediaBlocks(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{/);
    assert.ok(blocks.length > 0, 'components.css should carry at least one reduced-motion block');
    const spinnerBlock = blocks.find((b) => /\.spinner\b/.test(b));
    assert.ok(spinnerBlock, '.spinner should be covered by some reduced-motion block');
    assert.ok(/animation:\s*none/.test(spinnerBlock), 'spinner animation should be disabled, not the element hidden');
    assert.ok(!/\.spinner[^{]*\{[^}]*display:\s*none/.test(css), 'spinner must not be hidden entirely');
});

test('components.css skeleton loader keeps its existing reduced-motion override', () => {
    const css = read('components.css');
    assert.ok(/\.skeleton\s*\{[\s\S]*?animation:\s*skeleton-loading/.test(css));
    const blocks = extractAllMediaBlocks(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{/);
    assert.ok(blocks.some((b) => /\.skeleton\b/.test(b)));
});

// 3. Care search has a visible focus replacement when outline is removed
test('care.css search input removes native outline but the wrapper gets a focus-within ring', () => {
    const css = read('care.css');
    const inputBlock = extractBlock(css, /\.care-search-bar \.search-field input/);
    assert.ok(inputBlock, 'search input rule should exist');
    assert.ok(/outline:\s*none/.test(inputBlock), 'input keeps outline: none (wrapper handles focus)');

    const focusWithinBlock = extractBlock(css, /\.care-search-bar \.search-field:focus-within/);
    assert.ok(focusWithinBlock, 'search field wrapper should define a :focus-within state');
    assert.ok(
        /border-color/.test(focusWithinBlock) && /box-shadow/.test(focusWithinBlock),
        'focus-within state should give a visible ring (border + shadow)'
    );
});

// 4. Notifications navigable item has strong focus-visible treatment
test('notifications.css navigable item has a real outline on :focus-visible', () => {
    const css = read('notifications.css');
    const blocks = extractAllBlocks(css, /\.notif-page-item\.navigable:focus-visible/);
    assert.ok(blocks.length > 0, ':focus-visible rule(s) should exist for navigable items');
    const strongOutlineBlock = blocks.find((b) => /outline:\s*\d/.test(b));
    assert.ok(strongOutlineBlock, 'at least one :focus-visible block should set a real (non-zero) outline');
});

// 5. Confirmed small chat/sidebar/dashboard controls get >=44px touch hit-area
test('chat.css enlarges .input-clear to 44px under the touch breakpoint', () => {
    const css = read('chat.css');
    const block = extractMediaBlock(css, /@media\s*\(max-width:\s*1024px\)\s*\{/);
    assert.ok(block, 'chat.css should have a max-width:1024px block');
    const inputClear = extractBlock(block, /\.input-clear/);
    assert.ok(inputClear, '.input-clear should be targeted in the touch breakpoint');
    assert.ok(/width:\s*44px/.test(inputClear) && /height:\s*44px/.test(inputClear));
});

test('sidebar.css enlarges .sidebar-item-btn to 44px under the touch breakpoint', () => {
    const css = read('sidebar.css');
    const block = extractMediaBlock(css, /@media\s*\(max-width:\s*1024px\)\s*\{/);
    assert.ok(block, 'sidebar.css should have a max-width:1024px block');
    const btn = extractBlock(block, /\.sidebar-item-btn/);
    assert.ok(btn, '.sidebar-item-btn should be targeted in the touch breakpoint');
    assert.ok(/width:\s*44px/.test(btn) && /height:\s*44px/.test(btn));
});

test('dashboard.css enlarges .dashboard-item-btn to 44px under the touch breakpoint', () => {
    const css = read('dashboard.css');
    const block = extractMediaBlock(css, /@media\s*\(max-width:\s*1024px\)\s*\{/);
    assert.ok(block, 'dashboard.css should have a max-width:1024px block');
    const btn = extractBlock(block, /\.dashboard-item-btn/);
    assert.ok(btn, '.dashboard-item-btn should be targeted in the touch breakpoint');
    assert.ok(/width:\s*44px/.test(btn) && /height:\s*44px/.test(btn));
});

// 6. Map interactive controls already have touch-target coverage
test('map.css interactive controls already meet the 44px touch target', () => {
    const css = read('map.css');
    const mapControlBtn = extractBlock(css, /\.map-control-btn(?![\w-])/);
    assert.ok(mapControlBtn, '.map-control-btn base rule should exist');
    assert.ok(/width:\s*44px/.test(mapControlBtn) && /height:\s*44px/.test(mapControlBtn));

    const zoomBlock = extractMediaBlock(css, /@media\s*\(max-width:\s*1024px\)\s*\{/);
    assert.ok(zoomBlock, 'map.css should have a max-width:1024px block for leaflet zoom controls');
    assert.ok(/\.leaflet-control-zoom a[^{]*\{[^}]*width:\s*44px/.test(zoomBlock));

    const mobileMenuBlock = extractMediaBlock(css, /@media\s*\(max-width:\s*768px\)\s*\{/);
    assert.ok(mobileMenuBlock, 'map.css should have a max-width:768px block for the location menu');
    assert.ok(/\.location-menu-item,\s*\n?\s*\.location-district-btn\s*\{[^}]*min-height:\s*44px/.test(mobileMenuBlock));
});

// 7. Decorative small elements are not accidentally globally enlarged
test('decorative map elements (markers, clusters) are not given touch-target sizing', () => {
    const css = read('map.css');
    const markerPin = extractBlock(css, /\.marker-pin(?![\w-])/);
    assert.ok(markerPin, '.marker-pin rule should exist');
    assert.ok(!/min-width:\s*44px/.test(markerPin) && !/min-height:\s*44px/.test(markerPin));

    const cluster = extractBlock(css, /\.marker-cluster div/);
    assert.ok(cluster);
    assert.ok(!/min-width:\s*44px/.test(cluster));
});

test('sidebar/dashboard rename inputs (non-interactive-button decorative-adjacent) were not force-enlarged', () => {
    const sidebarCss = read('sidebar.css');
    const renameInput = extractBlock(sidebarCss, /\.sidebar-rename-input/);
    assert.ok(renameInput);
    assert.ok(!/min-height:\s*44px/.test(renameInput), 'rename input is a text field, not a touch button');
});

// 8. Global focus-visible rule still exists
test('main.css keeps the global :focus-visible contract', () => {
    const css = read('main.css');
    assert.ok(
        /:where\(a,\s*button,\s*input,\s*textarea,\s*select,\s*\[tabindex\]\):focus-visible\s*\{[^}]*outline:\s*3px/.test(css),
        'global focus-visible outline rule should be intact'
    );
});

// Conditional-fix files: verify focus behavior is genuinely already acceptable
// (they already carry a :focus ring, so no outline: none regression exists)
for (const [file, selector] of [
    ['ai-tools.css', '.chip-input-group input'],
    ['appointments.css', '.wizard-textarea'],
    ['feedback.css', '.feedback-textarea'],
]) {
    test(`${file} ${selector} keeps a visible :focus ring alongside its outline: none`, () => {
        const css = read(file);
        const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const focusBlock = extractBlock(css, new RegExp(`${escaped}:focus`));
        assert.ok(focusBlock, `${selector}:focus rule should exist`);
        assert.ok(/border-color/.test(focusBlock) && /box-shadow/.test(focusBlock));
    });
}

console.log(`${passCount} passing`);
if (process.exitCode === 1) {
    console.error('interaction-accessibility-ui: FAILURES ABOVE');
} else {
    console.log('interaction-accessibility-ui: all checks passed');
}
