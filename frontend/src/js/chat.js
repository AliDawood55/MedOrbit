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

    function isArLang() {
        return (document.documentElement.lang || 'ar') === 'ar';
    }

    /**
     * Sets the active conversation and notifies the rest of the app
     * (the conversation sidebar listens for this to update its active
     * highlight and refresh the list) without coupling chat.js to sidebar.js.
     */
    function setConversationId(id) {
        conversationId = id || null;
        window.dispatchEvent(new CustomEvent('chat:conversationChanged', {
            detail: { conversationId }
        }));
    }

    function getConversationId() {
        return conversationId;
    }

    function clearChat() {
        setConversationId(null);
        lastPlaces = [];
        const el = document.getElementById('chatMessages');
        if (el) el.innerHTML = '';
        renderWelcome();
        hideSuggestions();

        // Clear map
        if (MapApp?.clearResults) {
            MapApp.clearResults();
        }
    }

    /**
     * Loads a past conversation (from the sidebar) and replays its
     * messages + last known places into the chat panel and map.
     */
    async function loadConversation(id) {
        if (!id || isProcessing) return;

        const el = document.getElementById('chatMessages');
        if (!el) return;

        try {
            const res = await API.conversations.get(id);
            const data = res?.data;
            if (!data) return;

            setConversationId(data.conversation?.id || id);

            const places = (data.places || []).map((p) => ({
                id: p.id,
                name: p.place_name,
                lat: parseFloat(p.latitude),
                lng: parseFloat(p.longitude),
                type: p.place_type,
                address: p.address,
                phone: p.phone,
                distance: p.distance_km != null ? Number(p.distance_km) * 1000 : null,
                rating: p.rating
            }));
            lastPlaces = places;

            el.innerHTML = '';
            hideSuggestions();

            (data.messages || []).forEach((m) => {
                if (m.message_type === 'user') {
                    appendUserMessage(m.message_text);
                } else {
                    const meta = m.metadata || {};
                    appendBotMessage({
                        reply: m.message_text,
                        intent: m.intent,
                        places: meta.places || [],
                        doctors: meta.doctors || [],
                        suggestions: []
                    }, { skipMapUpdate: true });
                }
            });

            if (MapApp?.clearResults) MapApp.clearResults();
            if (places.length > 0 && MapApp?.renderPlaces) {
                MapApp.renderPlaces(places);
            }

            scroll(el);

        } catch (err) {
            console.error('Chat: failed to load conversation', err);
            if (typeof Toast !== 'undefined') {
                Toast.error(isArLang() ? 'تعذر تحميل المحادثة' : 'Could not load this conversation');
            }
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
        hideSuggestions();

        const input = document.getElementById('chatInput');
        if (input) {
            input.value = '';
            const clearBtn = document.getElementById('clearInputBtn');
            if (clearBtn) clearBtn.style.display = 'none';
        }

        appendUserMessage(text);

        showTyping();

        // Never silently drop location: if a fix is already in, use it; if
        // one is actively resolving, wait briefly rather than send without
        // it; otherwise proceed without coords and say so in the reply.
        let loc = null;
        let locationPending = false;
        if (typeof Location !== 'undefined') {
            const state = Location.getState();
            loc = state.coords;
            if (!loc && state.status === 'locating') {
                locationPending = true;
                loc = await Location.waitForFix(2500);
            }
        }

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

            // Track conversation ID (also lets the sidebar pick up new/updated conversations)
            if (data?.conversationId) {
                setConversationId(data.conversationId);
            }

            appendBotMessage(data);

            // If we sent without coords, tell the user why results (if any)
            // aren't distance-ranked — never fail silently.
            if (!payload.latitude) {
                appendLocationNote(locationPending);
            }

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

    function appendBotMessage(data, opts = {}) {

        const el = document.getElementById('chatMessages');
        if (!el) return;

        const reply = data?.reply || '';
        const intent = data?.intent || '';
        const places = Array.isArray(data?.places) ? data.places : [];
        const doctors = Array.isArray(data?.doctors) ? data.doctors : [];
        const suggestions = Array.isArray(data?.suggestions) ? data.suggestions : [];

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

            if (!opts.skipMapUpdate) {
                // Render markers on map
                if (MapApp?.renderPlaces) {
                    MapApp.renderPlaces(places);
                }

                // Highlight first place
                if (MapApp?.highlightPlace) {
                    MapApp.highlightPlace(places[0]);
                }

                // Draw route to first place (with safe location waiting)
                if (MapApp?.drawRoute) {
                    drawRouteSafely(places[0]);
                }
            }

            // Render clickable cards
            renderPlaceCards(el, places);

        } else if (intent === 'show_route' && lastPlaces.length > 0) {

            // show_route without new places — reuse cached places
            if (!opts.skipMapUpdate && MapApp?.renderPlaces) {
                MapApp.renderPlaces(lastPlaces);
            }

            renderPlaceCards(el, lastPlaces);

            // Draw route to first cached place
            if (!opts.skipMapUpdate && MapApp?.drawRoute) {
                drawRouteSafely(lastPlaces[0]);
            }
        }

        // ============================================
        // RENDER DOCTOR CARDS
        // ============================================
        if (doctors.length > 0) {
            renderDoctorCards(el, doctors);
        }

        scroll(el);

        // ============================================
        // SUGGESTION CHIPS (for the latest bot reply only)
        // ============================================
        renderSuggestions(suggestions);
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
     * Renders doctor result cards (find_doctor intent).
     * Purely informational for now — doctor profile pages land in a later phase.
     */
    function renderDoctorCards(container, doctors) {

        if (!doctors || doctors.length === 0) return;

        const isAr = isArLang();
        const cardsContainer = document.createElement('div');
        cardsContainer.className = 'cards doctor-cards';

        doctors.forEach((d) => {

            const card = document.createElement('div');
            card.className = 'doctor-card';

            const initials = (d.name || '?').trim().charAt(0).toUpperCase();
            const ratingText = d.rating != null ? Number(d.rating).toFixed(1) : null;
            const acceptingBadge = d.isAccepting === false
                ? '<span class="badge badge-danger">' + (isAr ? 'لا يستقبل حالياً' : 'Not accepting') + '</span>'
                : (d.isAccepting ? '<span class="badge badge-success">' + (isAr ? 'يستقبل مرضى جدد' : 'Accepting patients') + '</span>' : '');

            card.innerHTML =
                '<div class="doctor-card-avatar">' +
                    (d.image ? '<img src="' + escape(d.image) + '" alt="">' : escape(initials)) +
                '</div>' +
                '<div class="doctor-card-body">' +
                    '<div class="doctor-card-name">' + escape(d.name || '') + '</div>' +
                    (d.specialty ? '<div class="doctor-card-specialty">' + escape(d.specialty) + '</div>' : '') +
                    '<div class="doctor-card-meta">' +
                        (ratingText ? '<span class="rating"><span class="rating-stars">★</span><span class="rating-value">' + ratingText + '</span></span>' : '') +
                        (d.experience != null ? '<span>' + escape(String(d.experience)) + ' ' + (isAr ? 'سنة خبرة' : 'yrs exp.') + '</span>' : '') +
                        (d.fee != null ? '<span>' + escape(String(d.fee)) + ' ₪</span>' : '') +
                    '</div>' +
                    (acceptingBadge ? '<div class="doctor-card-badge">' + acceptingBadge + '</div>' : '') +
                '</div>';

            cardsContainer.appendChild(card);
        });

        container.appendChild(cardsContainer);
    }

    /**
     * Renders tappable suggestion chips for the latest bot reply.
     */
    function renderSuggestions(suggestions) {
        const el = document.getElementById('quickReplies');
        if (!el) return;

        if (!suggestions || suggestions.length === 0) {
            hideSuggestions();
            return;
        }

        el.innerHTML = '';
        suggestions.forEach((text) => {
            const chip = document.createElement('button');
            chip.type = 'button';
            chip.className = 'quick-reply-chip';
            chip.textContent = text;
            chip.addEventListener('click', () => handleSend(text));
            el.appendChild(chip);
        });
        el.style.display = 'flex';
    }

    function hideSuggestions() {
        const el = document.getElementById('quickReplies');
        if (!el) return;
        el.style.display = 'none';
        el.innerHTML = '';
    }

    /**
     * Safely draw route — waits (briefly) for a location fix via the shared
     * Location module instead of polling MapApp directly.
     */
    async function drawRouteSafely(destination) {

        if (!destination || destination.lat == null || destination.lng == null) return;
        if (typeof Location === 'undefined' || typeof MapApp === 'undefined') return;

        const state = Location.getState();
        let user = state.coords;

        if (!user && state.status === 'locating') {
            user = await Location.waitForFix(MAX_LOCATION_WAIT_ATTEMPTS * LOCATION_WAIT_INTERVAL_MS);
        }

        if (
            user &&
            user.lat != null &&
            user.lng != null &&
            !isNaN(user.lat) &&
            !isNaN(user.lng)
        ) {
            MapApp.drawRoute(user, destination);
        } else {
            console.warn('Route drawing skipped: user location not available');
        }
    }

    /**
     * Shown whenever a message was sent without coordinates, so the user
     * understands why results (if any) aren't distance-ranked, instead of
     * the location just silently being missing.
     */
    function appendLocationNote(wasPending) {
        const el = document.getElementById('chatMessages');
        if (!el) return;

        const isAr = isArLang();
        const text = wasPending
            ? (isAr ? 'ℹ️ لم يتم تحديد موقعك بعد، لذا لم يتم ترتيب النتائج حسب القرب.' : "ℹ️ Your location wasn't ready yet, so results aren't distance-ranked.")
            : (isAr ? 'ℹ️ موقعك غير محدد، لذا لم يتم ترتيب النتائج حسب القرب. يمكنك تحديده من الأعلى.' : "ℹ️ Your location isn't set, so results aren't distance-ranked. You can set it from the picker above.");

        const div = document.createElement('div');
        div.className = 'message bot location-note';
        div.innerHTML = '<div class="message-bubble">' + text + '</div>';

        el.appendChild(div);
        scroll(el);
    }

    function handleError(err) {

        const el = document.getElementById('chatMessages');
        if (!el) return;

        const msg = err?.message || 'حدث خطأ غير متوقع';
        const isAr = isArLang();
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

        const isAr = isArLang();

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
        clearChat,
        loadConversation,
        getConversationId
    };

})();
