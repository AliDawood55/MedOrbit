class ProfileValidationError extends Error {
    constructor(message) {
        super(message);
        this.statusCode = 400;
        this.code = 'VALIDATION_ERROR';
    }
}

function hasAny(source, keys) {
    return keys.some((key) => Object.prototype.hasOwnProperty.call(source, key));
}

function boundedText(source, keys, label, maxLength, { nullable = true } = {}) {
    if (!hasAny(source, keys)) return { provided: false, value: undefined };
    const key = keys.find((candidate) => Object.prototype.hasOwnProperty.call(source, candidate));
    const raw = source[key];
    if (raw === null && nullable) return { provided: true, value: null };
    if (typeof raw !== 'string') throw new ProfileValidationError(`${label} must be text`);
    const value = raw.trim();
    if (!value) {
        if (nullable) return { provided: true, value: null };
        throw new ProfileValidationError(`${label} is required`);
    }
    if (value.length > maxLength) {
        throw new ProfileValidationError(`${label} must not exceed ${maxLength} characters`);
    }
    return { provided: true, value };
}

function boundedTags(source, keys, label, maxItems, maxItemLength = 80) {
    if (!hasAny(source, keys)) return { provided: false, value: undefined };
    const key = keys.find((candidate) => Object.prototype.hasOwnProperty.call(source, candidate));
    const raw = source[key];
    if (!Array.isArray(raw)) throw new ProfileValidationError(`${label} must be an array`);

    const values = [];
    const seen = new Set();
    for (const item of raw) {
        if (typeof item !== 'string') throw new ProfileValidationError(`${label} entries must be text`);
        const value = item.trim().replace(/\s+/g, ' ');
        if (!value) continue;
        if (value.length > maxItemLength) {
            throw new ProfileValidationError(`${label} entries must not exceed ${maxItemLength} characters`);
        }
        const normalized = value.toLocaleLowerCase('en-US');
        if (seen.has(normalized)) continue;
        seen.add(normalized);
        values.push(value);
    }
    if (values.length > maxItems) {
        throw new ProfileValidationError(`${label} must not contain more than ${maxItems} entries`);
    }
    return { provided: true, value: values };
}

function boundedInteger(source, keys, label, min, max) {
    if (!hasAny(source, keys)) return { provided: false, value: undefined };
    const key = keys.find((candidate) => Object.prototype.hasOwnProperty.call(source, candidate));
    const value = Number(source[key]);
    if (!Number.isInteger(value) || value < min || value > max) {
        throw new ProfileValidationError(`${label} must be an integer between ${min} and ${max}`);
    }
    return { provided: true, value };
}

module.exports = {
    ProfileValidationError,
    boundedText,
    boundedTags,
    boundedInteger,
};
