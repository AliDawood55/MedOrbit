#!/usr/bin/env node
/**
 * Extracts the ar/en dictionary from the legacy frontend's i18n.js into
 * next-intl message catalogs, without hand-retyping any string.
 *
 * - Parses `frontend/src/js/i18n.js`'s `const dict = { ar: {...}, en: {...} }`
 *   by locating the balanced object literal (respecting string boundaries,
 *   so `{rating}`-style interpolation braces inside values don't break the
 *   scan) and evaluating it as real JS — the only way to get the exact
 *   strings without re-parsing escape sequences by hand.
 * - Reports full ar/en key parity across the ENTIRE legacy dictionary, so
 *   drift is caught even for namespaces this phase doesn't migrate yet.
 * - Writes ONLY the "shared foundation" namespaces approved for Phase 1A
 *   into frontend-next/messages/{ar,en}.json, nested (next-intl expects
 *   nested JSON, legacy uses flat "a.b.c" keys).
 *
 * Re-run this script in later phases after widening SHARED_NAMESPACES /
 * BARE_KEYS — it will re-derive both catalogs from the same source of
 * truth instead of accumulating hand edits.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SOURCE = path.resolve(__dirname, "../../frontend/src/js/i18n.js");
const OUT_DIR = path.resolve(__dirname, "../messages");

// Phase 1A scope: only namespaces actually used by the foundation layout
// (root html/body, minimal placeholder page, theme/locale toggles).
// Widen this list in later phases as real pages need more namespaces.
const SHARED_NAMESPACES = ["common", "brand", "footer"];
const BARE_KEYS = ["language", "theme"];

function extractDictSource(source) {
  const marker = "const dict = {";
  const start = source.indexOf(marker);
  if (start === -1) throw new Error("Could not find `const dict = {` in i18n.js");

  const braceStart = start + marker.length - 1; // index of the opening `{`
  let depth = 0;
  let inString = false;
  let quote = "";
  let escaped = false;
  let inLineComment = false;

  for (let i = braceStart; i < source.length; i++) {
    const ch = source[i];

    if (inLineComment) {
      if (ch === "\n") inLineComment = false;
      continue;
    }

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === quote) {
        inString = false;
      }
      continue;
    }

    if (ch === "/" && source[i + 1] === "/") {
      inLineComment = true;
      i++;
      continue;
    }

    if (ch === "'" || ch === '"' || ch === "`") {
      inString = true;
      quote = ch;
      continue;
    }

    if (ch === "{") depth++;
    if (ch === "}") {
      depth--;
      if (depth === 0) {
        return source.slice(braceStart, i + 1);
      }
    }
  }

  throw new Error("Could not find the end of `dict` — unbalanced braces");
}

function nest(flatEntries) {
  const root = {};
  for (const [key, value] of flatEntries) {
    const parts = key.split(".");
    let node = root;
    for (let i = 0; i < parts.length - 1; i++) {
      node[parts[i]] ??= {};
      node = node[parts[i]];
    }
    node[parts[parts.length - 1]] = value;
  }
  return root;
}

function main() {
  const source = readFileSync(SOURCE, "utf8");
  const dictSource = extractDictSource(source);

  // Trusted local source file (not user input) — evaluating it directly is
  // the only reliable way to get exact string values incl. escapes.
  const dict = new Function(`"use strict"; return (${dictSource});`)();

  if (!dict.ar || !dict.en) {
    throw new Error("Expected dict.ar and dict.en to both exist");
  }

  const arKeys = new Set(Object.keys(dict.ar));
  const enKeys = new Set(Object.keys(dict.en));
  const missingInEn = [...arKeys].filter((k) => !enKeys.has(k));
  const missingInAr = [...enKeys].filter((k) => !arKeys.has(k));

  console.log(`Legacy dictionary: ${arKeys.size} ar keys, ${enKeys.size} en keys`);
  if (missingInEn.length || missingInAr.length) {
    console.warn("\n⚠ Key parity drift in the FULL legacy dictionary (not blocking — informational for later phases):");
    if (missingInEn.length) console.warn(`  in ar, missing in en (${missingInEn.length}):`, missingInEn);
    if (missingInAr.length) console.warn(`  in en, missing in ar (${missingInAr.length}):`, missingInAr);
  } else {
    console.log("✓ Full dictionary key parity: ar and en match exactly.");
  }

  const isShared = (key) => {
    if (BARE_KEYS.includes(key)) return true;
    const [namespace] = key.split(".");
    return SHARED_NAMESPACES.includes(namespace);
  };

  for (const locale of ["ar", "en"]) {
    const entries = Object.entries(dict[locale]).filter(([key]) => isShared(key));
    const nested = nest(entries);
    const json = JSON.stringify(nested, null, 2) + "\n";
    const outPath = path.join(OUT_DIR, `${locale}.json`);
    writeFileSync(outPath, json, "utf8");
    console.log(`Wrote ${entries.length} shared-foundation keys -> ${path.relative(process.cwd(), outPath)}`);
  }
}

main();
