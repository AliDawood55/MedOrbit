exports.validateIntent = (intent, confidence) => {
    const CONFIDENCE_THRESHOLD = 0.4;

    if (confidence < CONFIDENCE_THRESHOLD) {
        return {
            isValid: false,
            fallback: true
        };
    }

    return {
        isValid: true,
        fallback: false
    };
};