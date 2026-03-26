    document.addEventListener('DOMContentLoaded', function () {
        'use strict';

        const indexEnabled = '{__html_show_index}' === '1';
        if (!indexEnabled) return;

        const keywords = Array.from(document.querySelectorAll('span.keyword'));
        if (!keywords.length) return;

        // --- 1. Attribuer un id unique à chaque occurrence ---
        const keywordMap = {};

        keywords.forEach((span) => {
            const term = span.textContent.trim();
            if (!keywordMap[term]) keywordMap[term] = [];
            const idx = keywordMap[term].length;
            span.id = `kw-${term.toLowerCase().replace(/\s+/g, '-')}-${idx}`;
            keywordMap[term].push(span);
        });

        // --- 2. Barre de navigation flottante ---
        const navbar = document.createElement('div');
        navbar.id = 'adp-kw-navbar';
        navbar.style.display = 'none';
        navbar.innerHTML = `
            <span id="adp-kw-navbar-term"></span>
            <button id="adp-kw-prev" title="Occurrence précédente">&#8249;</button>
            <span id="adp-kw-counter"></span>
            <button id="adp-kw-next" title="Occurrence suivante">&#8250;</button>
            <button id="adp-kw-close" title="Fermer">✕</button>
        `;
        document.body.appendChild(navbar);

        let activeTerm = null;
        let activeCursor = 0;

        function highlightCurrent() {
            keywordMap[activeTerm].forEach(span => span.classList.remove('adp-kw-active'));
            const target = keywordMap[activeTerm][activeCursor];
            target.classList.add('adp-kw-active');
            target.scrollIntoView({ behavior: 'smooth', block: 'center' });
            document.getElementById('adp-kw-counter').textContent =
                `${activeCursor + 1} / ${keywordMap[activeTerm].length}`;
        }

        function openNavbar(term, cursor) {
            if (activeTerm && activeTerm !== term) {
                keywordMap[activeTerm].forEach(span => span.classList.remove('adp-kw-active'));
            }
            activeTerm = term;
            activeCursor = cursor;

            // une seule occurrence : scroll direct, pas de navbar
            if (keywordMap[term].length === 1) {
                const target = keywordMap[term][0];
                target.classList.add('adp-kw-active');
                target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                return;
            }

            document.getElementById('adp-kw-navbar-term').textContent = `« ${term} »`;
            navbar.style.display = 'flex';
            highlightCurrent();
        }

        function closeNavbar() {
            if (activeTerm) {
                keywordMap[activeTerm].forEach(span => span.classList.remove('adp-kw-active'));
            }
            activeTerm = null;
            navbar.style.display = 'none';
        }

        document.getElementById('adp-kw-prev').addEventListener('click', () => {
            activeCursor = (activeCursor - 1 + keywordMap[activeTerm].length) % keywordMap[activeTerm].length;
            highlightCurrent();
        });

        document.getElementById('adp-kw-next').addEventListener('click', () => {
            activeCursor = (activeCursor + 1) % keywordMap[activeTerm].length;
            highlightCurrent();
        });

        document.getElementById('adp-kw-close').addEventListener('click', closeNavbar);

        document.addEventListener('click', (e) => {
            if (
                activeTerm &&
                !e.target.closest('#adp-kw-navbar') &&
                !e.target.closest('span.keyword') &&
                !e.target.closest('.adp-index-tag')
            ) {
                closeNavbar();
            }
        });

        // --- 3. Clic sur un span.keyword dans le texte ---
        keywords.forEach((span) => {
            span.addEventListener('click', (e) => {
                e.stopPropagation();
                const term = span.textContent.trim();
                const cursor = keywordMap[term].indexOf(span);
                openNavbar(term, cursor);
            });
        });

        // --- 4. Construire la zone de tags ---
        const position = '{__html_index_position}' === 'start' ? 'start' : 'end';

        const tagsContainer = document.createElement('div');
        tagsContainer.id = 'adp-index-tags';

        Object.keys(keywordMap).sort().forEach((term) => {
            const occurrences = keywordMap[term];

            const tag = document.createElement('span');
            tag.className = 'adp-index-tag';
            tag.innerHTML = occurrences.length > 1
                ? `${term} <span class="adp-index-badge">${occurrences.length}</span>`
                : term;
            tag.setAttribute('title', `${occurrences.length} occurrence(s)`);
            tag.setAttribute('role', 'button');
            tag.tabIndex = 0;

            tag.addEventListener('click', (e) => {
                e.stopPropagation();
                const cursor = (activeTerm === term) ? activeCursor : 0;
                openNavbar(term, cursor);
            });

            tagsContainer.appendChild(tag);
        });

        // --- 5. Insérer la zone de tags ---
        const content = document.getElementById('content');

        if (position === 'start') {
            content.prepend(tagsContainer);
        } else {
            content.appendChild(tagsContainer);
        }

    });