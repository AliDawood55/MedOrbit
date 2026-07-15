const Chat = (() => {

    let isProcessing = false;
    let activeController = null;
    let conversationId = null;

    // Cache last places for follow-up commands (show_route)
    let lastPlaces = [];

    // Max attempts to wait for user location before giving up
    const MAX_LOCATION_WAIT_ATTEMPTS = 10;
    const LOCATION_WAIT_INTERVAL_MS = 500;

    function init() {
        renderWelcome();
        attachEvents();
    }

    function clearChat() {
        conversationId = null;
        lastPlaces = [];
        const el = document.getElementById('chatMessages');
        if (el) el.innerHTML = '';
        renderWelcome();

        // Clear map
        if (MapApp?.clearResults) {
            MapApp.clearResults();
        }
    }

    async function handleSend(text) {

        if (!text || isProcessing) return;

        // Abort previous request if still pending
        if (activeController) {
            try { activeController.abort(); } catch (e) { /* ignore */ }
        }

        activeController = API.makeCancellable();
        isProcessing = true;
        setProcessingState(true);

        const input = document.getElementById('chatInput');
        if (input) {
            input.value = '';
            const clearBtn = document.getElementById('clearInputBtn');
            if (clearBtn) clearBtn.style.display = 'none';
        }

        appendUserMessage(text);

        // Get user location safely — only if valid
        const loc = MapApp?.getUserLocation?.() || null;

        showTyping();

        try {

            const payload = { message: text };

            if (conversationId) {
                payload.conversationId = conversationId;
            }

            if (
                loc &&
                loc.lat != null &&
                loc.lng != null &&
                !isNaN(loc.lat) &&
                !isNaN(loc.lng) &&
                loc.lat !== 0 &&
                loc.lng !== 0
            ) {
                payload.latitude = Number(loc.lat);
                payload.longitude = Number(loc.lng);
            }

            const data = await API.sendChatMessage({
                ...payload,
                signal: activeController.signal
            });

            hideTyping();

            // Track conversation ID
            if (data?.conversationId) {
                conversationId = data.conversationId;
            }

            appendBotMessage(data);

        } catch (err) {

            hideTyping();

            // Don't show error if request was intentionally aborted
            if (err.name === 'AbortError') return;

            handleError(err);

        } finally {

            isProcessing = false;
            setProcessingState(false);
            activeController = null;
        }
    }

    function appendUserMessage(text) {

        const el = document.getElementById('chatMessages');
        if (!el) return;

        const div = document.createElement('div');
        div.className = 'message user';
        div.innerHTML = '<div class="message-bubble">' + escape(text) + '</div>';

        el.appendChild(div);
        scroll(el);
    }

    function appendBotMessage(data) {

        const el = document.getElementById('chatMessages');
        if (!el) return;

        const reply = data?.reply || '';
        const intent = data?.intent || '';
        const places = Array.isArray(data?.places) ? data.places : [];

        // Render bot text reply
        if (reply) {
            const msgDiv = document.createElement('div');
            msgDiv.className = 'message bot';
            msgDiv.innerHTML = '<div class="message-bubble">' + escape(reply).replace(/\n/g, '<br/>') + '</div>';
            el.appendChild(msgDiv);
        }

        // ============================================
        // UPDATE CACHED PLACES
        // Only update cache when new places arrive
        // ============================================
        if (places.length > 0) {
            lastPlaces = places;
        }

        // ============================================
        // RENDER MAP MARKERS + CARDS
        // ============================================
        if (places.length > 0) {

            // Render markers on map
            if (MapApp?.renderPlaces) {
                MapApp.renderPlaces(places);
            }

            // Highlight first place
            if (MapApp?.highlightPlace) {
                MapApp.highlightPlace(places[0]);
            }

            // Render clickable cards
            renderPlaceCards(el, places);

            // Draw route to first place (with safe location waiting)
            if (MapApp?.drawRoute) {
                drawRouteSafely(places[0]);
            }

        } else if (intent === 'show_route' && lastPlaces.length > 0) {

            // show_route without new places — reuse cached places
            if (MapApp?.renderPlaces) {
                MapApp.renderPlaces(lastPlaces);
            }

            renderPlaceCards(el, lastPlaces);

            // Draw route to first cached place
            if (MapApp?.drawRoute) {
                drawRouteSafely(lastPlaces[0]);
            }
        }

        scroll(el);
    }

    function renderPlaceCards(container, places) {

        if (!places || places.length === 0) return;

        const cardsContainer = document.createElement('div');
        cardsContainer.className = 'cards';

        places.forEach((p, index) => {

            const card = document.createElement('div');
            card.className = 'clinic-card';
            card.dataset.lat = p.lat;
            card.dataset.lng = p.lng;
            card.dataset.name = p.name || '';
            card.dataset.index = index;

            const distText = p.distance
                ? (Number(p.distance) / 1000).toFixed(2) + ' كم'
                : '';

            card.innerHTML =
                '<div class="clinic-name">' + escape(p.name) + '</div>' +
                (p.phone ? '<div class="clinic-phone">' + escape(p.phone) + '</div>' : '') +
                (distText ? '<div class="clinic-meta">' + distText + '</div>' : '');

            card.addEventListener('click', () => {

                const place = {
                    lat: parseFloat(card.dataset.lat),
                    lng: parseFloat(card.dataset.lng),
                    name: card.dataset.name
                };

                if (MapApp?.highlightPlace) {
                    MapApp.highlightPlace(place);
                }

                if (MapApp?.drawRoute) {
                    drawRouteSafely(place);
                }
            });

            cardsContainer.appendChild(card);
        });

        container.appendChild(cardsContainer);
    }

    /**
     * Safely draw route — waits for valid user location
     * with a maximum retry limit to prevent infinite polling
     */
    function drawRouteSafely(destination) {

        if (!destination || destination.lat == null || destination.lng == null) return;

        let attempts = 0;

        const tryDraw = () => {

            const user = MapApp.getUserLocation();

            if (
                user &&
                user.lat != null &&
                user.lng != null &&
                !isNaN(user.lat) &&
                !isNaN(user.lng)
            ) {
                MapApp.drawRoute(user, destination);
                return;
            }

            attempts++;

            if (attempts < MAX_LOCATION_WAIT_ATTEMPTS) {
                setTimeout(tryDraw, LOCATION_WAIT_INTERVAL_MS);
            } else {
                console.warn('Route drawing skipped: user location not available after', MAX_LOCATION_WAIT_ATTEMPTS, 'attempts');
            }
        };

        tryDraw();
    }

    function handleError(err) {

        const el = document.getElementById('chatMessages');
        if (!el) return;

        const msg = err?.message || 'حدث خطأ غير متوقع';
        const isAr = (document.documentElement.lang || 'ar') === 'ar';
        const errorText = isAr ? '⚠️ حدث خطأ في الاتصال. يرجى المحاولة مرة أخرى.' : '⚠️ Connection error. Please try again.';

        const div = document.createElement('div');
        div.className = 'message bot error';
        div.innerHTML = '<div class="message-bubble">' + errorText + '</div>';

        el.appendChild(div);
        scroll(el);
    }

    function setProcessingState(p) {
        const btn = document.getElementById('sendBtn');
        if (btn) btn.disabled = p;
    }

    function showTyping() {
        const el = document.getElementById('chatTyping');
        if (el) el.style.display = 'flex';
    }

    function hideTyping() {
        const el = document.getElementById('chatTyping');
        if (el) el.style.display = 'none';
    }

    function scroll(el) {
        if (el) el.scrollTop = el.scrollHeight;
    }

    function renderWelcome() {
        const el = document.getElementById('chatMessages');
        if (!el) return;

        const isAr = (document.documentElement.lang || 'ar') === 'ar';

        const welcomeText = isAr
            ? '👋 أهلاً بك في MedOrbit!\nيمكنني مساعدتك في البحث عن عيادات، صيدليات، مستشفيات، والأطباء الأقرب إليك.\n\nجرّب أن تسأل:\n• أقرب صيدلية\n• أقرب عيادة\n• أقرب مستشفى'
            : '👋 Welcome to MedOrbit!\nI can help you find the nearest clinics, pharmacies, hospitals, and doctors.\n\nTry asking:\n• Nearest pharmacy\n• Nearest clinic\n• Nearest hospital';

        el.innerHTML = '<div class="message bot welcome"><div class="message-bubble">' +
            escape(welcomeText).replace(/\n/g, '<br/>') +
            '</div></div>';
    }

    function attachEvents() {

        const form = document.getElementById('chatForm');
        const input = document.getElementById('chatInput');

        if (!form || !input) {
            console.error('Chat: form or input not found');
            return;
        }

        form.addEventListener('submit', (e) => {
            e.preventDefault();
            const text = input.value.trim();
            if (!text) return;
            handleSend(text);
        });

        input.addEventListener('input', () => {
            const btn = document.getElementById('sendBtn');
            const clearBtn = document.getElementById('clearInputBtn');
            if (btn) btn.disabled = !input.value.trim();
            if (clearBtn) clearBtn.style.display = input.value.trim() ? 'flex' : 'none';
        });
    }

    function escape(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    return {
        init,
        handleSend,
        clearChat
    };

})();