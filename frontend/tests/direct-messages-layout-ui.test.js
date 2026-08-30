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

function frontendFile(relativePath) {
    return fs.readFileSync(path.resolve(__dirname, '..', relativePath), 'utf8');
}

/**
 * Return the declaration body of the first top-level rule whose selector list
 * matches `selector` exactly. Good enough for the flat, hand-authored
 * direct-messages.css (no nested at-rules around these blocks).
 */
function ruleBody(css, selector) {
    const stripped = css.replace(/\/\*[\s\S]*?\*\//g, '');
    const lines = stripped.split('\n');
    for (let i = 0; i < lines.length; i += 1) {
        const line = lines[i].trim();
        if (line === `${selector} {` || line === `${selector}{`) {
            const rest = stripped.slice(stripped.indexOf(lines[i]));
            return rest.slice(rest.indexOf('{') + 1, rest.indexOf('}'));
        }
    }
    return null;
}

console.log('\nDirect Messages responsive-layout contract tests\n');

const css = frontendFile('src/css/direct-messages.css');
const html = frontendFile('public/direct-messages.html');

// --- Regression: the thread-pane row layout must not depend on how many
// optional siblings (request banner, "load older") are currently displayed.
// The previous positional grid template silently handed .message-history an
// auto-sized row whenever those siblings were hidden, so a long conversation
// grew the pane and pushed the composer past the clipped shell.
const threadPane = ruleBody(css, '.thread-pane');
check('.thread-pane rule exists', threadPane !== null);
check('.thread-pane lays out as a flex column (count-independent)',
    /display:\s*flex/.test(threadPane) && /flex-direction:\s*column/.test(threadPane),
    threadPane || '');
check('.thread-pane no longer uses a positional grid-template-rows track list',
    !/grid-template-rows:\s*auto\s+auto\s+auto\s+minmax\(0,\s*1fr\)\s+auto/.test(css));
check('.thread-pane keeps min-height:0 so the history can actually shrink',
    /min-height:\s*0/.test(threadPane || ''));

const history = ruleBody(css, '.message-history');
check('.message-history is the single flexible, scrollable track',
    /flex:\s*1/.test(history || '') &&
    /min-height:\s*0/.test(history || '') &&
    /overflow:\s*auto/.test(history || ''),
    history || '');

check('the fixed thread rows (header, banner, load-older, composer) do not shrink',
    /\.thread-pane\s*>\s*\.thread-header[\s\S]{0,160}\.message-composer\s*\{\s*flex:\s*none/.test(
        css.replace(/\/\*[\s\S]*?\*\//g, ''),
    ));

const shell = ruleBody(css, '.messages-shell');
check('.messages-shell keeps a bounded viewport-relative height',
    /height:\s*(clamp\(|min\(|calc\(|\d)/.test(shell || '') &&
    /(vh|svh|dvh)/.test(shell || ''),
    shell || '');
check('.messages-shell pins its single row to minmax(0, 1fr)',
    /grid-template-rows:\s*minmax\(0,\s*1fr\)/.test(shell || ''));

// --- DOM ordering: one composer, sibling of the history, both inside the
// thread pane, and the whole shell sits before the global footer.
const composerCount = (html.match(/class="message-composer"/g) || []).length;
check('exactly one .message-composer exists (no duplicate composer hack)',
    composerCount === 1, `found ${composerCount}`);

const threadPaneOpen = html.indexOf('<section class="thread-pane">');
const threadPaneClose = html.indexOf('</section>', threadPaneOpen);
const historyIdx = html.indexOf('class="message-history"');
const composerIdx = html.indexOf('class="message-composer"');
const footerIdx = html.indexOf('class="site-footer"');
check('.message-history and .message-composer both live inside .thread-pane',
    historyIdx > threadPaneOpen && historyIdx < threadPaneClose &&
    composerIdx > threadPaneOpen && composerIdx < threadPaneClose);
check('.message-composer comes after .message-history in source order',
    composerIdx > historyIdx);
check('the chat shell is rendered before the global footer',
    threadPaneClose < footerIdx && footerIdx !== -1);

// --- The page must not resurrect a full-document scroll lock. A page-level
// `overflow: hidden` on the document, body, main, or the page wrapper would
// trap the user when the composer needs the viewport to scroll.
const documentScrollLock = ['html', 'body', 'body.site-page',
    'body.direct-messages-page', '.messages-page', 'main.messages-page']
    .some((selector) => {
        const body = ruleBody(css, selector);
        return body !== null && /overflow(-y)?:\s*hidden/.test(body);
    });
check('direct-messages.css never locks document/body/page scrolling', !documentScrollLock);

// --- Mobile single-pane switch still uses the flex column, not the old grid.
check('mobile .messages-thread-open .thread-pane opens as flex, not grid',
    /\.messages-thread-open\s+\.thread-pane\s*\{\s*display:\s*flex/.test(css) &&
    !/\.messages-thread-open\s+\.thread-pane\s*\{\s*display:\s*grid/.test(css));

console.log(`\nDirect Messages responsive-layout contract tests: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
