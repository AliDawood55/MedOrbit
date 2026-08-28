(function () {
    document.documentElement.setAttribute('data-auth-gate', 'pending');

    function f() {
        if (window.__medorbitAuthGateReady || window.__medorbitNavigatingAway) {
            return;
        }

        location.replace(
            'home.html?auth=unavailable&next=' +
            encodeURIComponent(
                location.pathname.split('/').pop() + location.search
            )
        );
    }

    window.addEventListener('load', function () {
        setTimeout(f, 0);
    });

    setTimeout(f, 20000);
})();