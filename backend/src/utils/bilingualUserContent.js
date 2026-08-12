'use strict';

const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);

function validationError(message) {
    const error = new Error(message);
    error.statusCode = 400;
    error.code = 'VALIDATION_ERROR';
    return error;
}

function normalizeText(value) {
    if (value === undefined) return undefined;
    if (value === null) return null;
    const text = String(value).trim();
    return text || null;
}

function firstProvided(body, keys) {
    for (const key of keys) {
        if (hasOwn(body, key)) return { provided: true, value: normalizeText(body[key]) };
    }
    return { provided: false, value: undefined };
}

/**
 * Accept one canonical user-content field while retaining legacy Arabic/English
 * payloads. Canonical input is copied verbatim (apart from outer whitespace)
 * to both existing columns; legacy input keeps the two historical values apart.
 */
function resolveBilingualUserContent(rawBody, options) {
    const body = rawBody && typeof rawBody === 'object' ? rawBody : {};
    const {
        canonicalKey,
        legacyArKeys,
        legacyEnKeys,
        label,
        maxLength,
        required = false,
    } = options;

    if (hasOwn(body, canonicalKey)) {
        const canonical = normalizeText(body[canonicalKey]);
        if (required && !canonical) throw validationError(`${label} is required`);
        if (canonical && maxLength && canonical.length > maxLength) {
            throw validationError(`${label} is too long`);
        }
        return {
            provided: true,
            source: 'canonical',
            canonical,
            ar: canonical,
            en: canonical,
            arProvided: true,
            enProvided: true,
        };
    }

    const ar = firstProvided(body, legacyArKeys);
    const en = firstProvided(body, legacyEnKeys);
    const provided = ar.provided || en.provided;
    const arValue = ar.value ?? null;
    const enValue = en.value ?? null;

    if (required && (!provided || (!arValue && !enValue))) {
        throw validationError(`${label} is required`);
    }
    if (maxLength && ((arValue && arValue.length > maxLength) || (enValue && enValue.length > maxLength))) {
        throw validationError(`${label} is too long`);
    }

    return {
        provided,
        source: provided ? 'legacy' : null,
        canonical: arValue || enValue || null,
        ar: arValue,
        en: enValue,
        arProvided: ar.provided && arValue !== null,
        enProvided: en.provided && enValue !== null,
    };
}

function withCanonicalContent(record, canonicalKey, arKey, enKey) {
    return {
        ...record,
        [canonicalKey]: record?.[arKey] || record?.[enKey] || null,
    };
}

module.exports = { resolveBilingualUserContent, withCanonicalContent };
