const API = (() => {

    const BASE_URL = 'http://127.0.0.1:3001/api';

    async function request(path, options = {}) {

        const url = BASE_URL + path;

        const response = await fetch(url, {
            method: options.method || 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: options.body ? JSON.stringify(options.body) : null,
            signal: options.signal
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data?.error?.message || 'Request failed');
        }

        return data;
    }

    async function sendChatMessage(params) {

        // Extract signal from params (not sent to server)
        const { signal, ...body } = params;

        const res = await request('/chat/message', {
            method: 'POST',
            body,
            signal
        });

        return res.data;
    }

    function makeCancellable() {
        return new AbortController();
    }

    return {
        sendChatMessage,
        makeCancellable
    };

})();