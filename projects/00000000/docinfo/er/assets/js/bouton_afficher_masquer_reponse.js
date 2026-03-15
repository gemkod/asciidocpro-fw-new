document.addEventListener('DOMContentLoaded', function () {
    'use strict';

    if (document.querySelector('link[href^="http://localhost:"]')) return;

    const toggleEnabled = '{adp_html_toggle_answer}' === '1';
    if (!toggleEnabled) return;

    const answers = Array.from(document.querySelectorAll('.sidebarblock.answer'));
    if (!answers.length) return;

    function findQuestionAbove(el) {
        let sibling = el.previousElementSibling;
        while (sibling) {
            if (sibling.classList.contains('question')) return sibling;
            sibling = sibling.previousElementSibling;
        }
        return null;
    }

    function findBtnFor(block) {
        const q = findQuestionAbove(block);
        return q ? q.querySelector('.adp-toggle-btn') : null;
    }

    answers.forEach((block) => {
        const questionBlock = findQuestionAbove(block);

        const btn = document.createElement('button');
        btn.className = 'adp-toggle-btn';
        btn.innerHTML = `<span class="adp-label">Cacher la correction</span>`;
        btn.setAttribute('aria-label', 'Afficher/masquer la correction');

        btn.addEventListener('click', () => {
            const hidden = block.classList.toggle('adp-hidden');
            btn.classList.toggle('is-hidden-state', hidden);
            btn.querySelector('.adp-label').textContent = hidden ? 'Voir la correction' : 'Cacher la correction';
            updateGlobalBtns();
        });

        if (questionBlock) {
            questionBlock.appendChild(btn);
        } else {
            block.parentNode.insertBefore(btn, block);
        }
    });

    const bar = document.createElement('div');
    bar.id = 'adp-global-bar';
    bar.innerHTML = `
    <button id="adp-btn-reveal">Tout révéler <span class="adp-badge" id="adp-count-hidden">0</span></button>
    <button id="adp-btn-hide">Tout masquer <span class="adp-badge" id="adp-count-visible">${answers.length}</span></button>
  `;
    document.body.appendChild(bar);

    const btnReveal = document.getElementById('adp-btn-reveal');
    const btnHide = document.getElementById('adp-btn-hide');

    function updateGlobalBtns() {
        const hiddenCount = answers.filter(b => b.classList.contains('adp-hidden')).length;
        const visibleCount = answers.length - hiddenCount;
        document.getElementById('adp-count-hidden').textContent = hiddenCount;
        document.getElementById('adp-count-visible').textContent = visibleCount;
        btnReveal.disabled = hiddenCount === 0;
        btnHide.disabled = visibleCount === 0;
    }

    function setAllAnswers(hide) {
        answers.forEach((block) => {
            block.classList.toggle('adp-hidden', hide);
            const btn = findBtnFor(block);
            if (btn) {
                btn.classList.toggle('is-hidden-state', hide);
                btn.querySelector('.adp-label').textContent = hide ? 'Voir la correction' : 'Cacher la correction';
            }
        });
        updateGlobalBtns();
    }

    btnReveal.addEventListener('click', () => setAllAnswers(false));
    btnHide.addEventListener('click', () => setAllAnswers(true));

    setAllAnswers(true);

});