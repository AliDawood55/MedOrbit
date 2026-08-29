document.addEventListener('DOMContentLoaded', () => {
    if (typeof I18n !== 'undefined') I18n.apply();
    if (typeof Theme !== 'undefined') Theme.apply();
    BillingSandbox.init();
});
