/**
 * MedOrbit v2 - Chip Input
 * Small reusable "type + Enter/button to add, click to remove" tag input,
 * shared by symptom-checker.html and drug-checker.html.
 */
const ChipInput = (() => {

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function create({ inputId, addBtnId, listId, initial = [], onChange } = {}) {
        let items = [...initial];

        function render() {
            const list = document.getElementById(listId);
            if (!list) return;

            list.innerHTML = items.map((item, i) =>
                '<span class="chip-tag">' + escapeHtml(item) +
                    '<button type="button" class="chip-remove" data-index="' + i + '" aria-label="Remove">' +
                        '<i class="fas fa-xmark"></i>' +
                    '</button>' +
                '</span>'
            ).join('');

            list.querySelectorAll('.chip-remove').forEach(btn => {
                btn.addEventListener('click', () => {
                    items.splice(parseInt(btn.dataset.index, 10), 1);
                    render();
                    onChange?.([...items]);
                });
            });
        }

        function add(value) {
            const v = (value || '').trim();
            if (!v || items.some(existing => existing.toLowerCase() === v.toLowerCase())) return false;
            items.push(v);
            render();
            onChange?.([...items]);
            return true;
        }

        function clear() {
            items = [];
            render();
            onChange?.([...items]);
        }

        const input = document.getElementById(inputId);
        input?.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                if (add(input.value)) input.value = '';
            }
        });

        document.getElementById(addBtnId)?.addEventListener('click', () => {
            if (add(input?.value)) input.value = '';
        });

        render();

        return {
            getItems: () => [...items],
            addItem: add,
            clear
        };
    }

    return { create };

})();
