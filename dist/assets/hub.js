document.addEventListener('DOMContentLoaded', function () {
  // OS Tabs Switcher
  const osTabs = document.querySelectorAll('.os-tab-btn');
  const macosView = document.getElementById('macos-showcase');
  const windowsView = document.getElementById('windows-showcase');

  function switchOS(target) {
    osTabs.forEach(function (tab) {
      if (tab.getAttribute('data-target-os') === target) {
        tab.classList.add('active');
        tab.setAttribute('aria-selected', 'true');
      } else {
        tab.classList.remove('active');
        tab.setAttribute('aria-selected', 'false');
      }
    });

    if (target === 'windows') {
      if (macosView) macosView.classList.add('hidden-view');
      if (windowsView) windowsView.classList.remove('hidden-view');
    } else {
      if (macosView) macosView.classList.remove('hidden-view');
      if (windowsView) windowsView.classList.add('hidden-view');
    }
  }

  osTabs.forEach(function (tab) {
    tab.addEventListener('click', function () {
      const os = tab.getAttribute('data-target-os');
      if (os) {
        switchOS(os);
        try {
          if (history.replaceState) {
            history.replaceState(null, null, '#' + (os === 'windows' ? 'windows' : 'macos'));
          }
        } catch (e) {}
      }
    });
  });

  // Check URL hash on load or change
  function checkHash() {
    if (window.location.hash === '#windows' || window.location.hash === '#windows-apps' || window.location.hash === '#windows-security') {
      switchOS('windows');
      const el = document.getElementById(window.location.hash.substring(1));
      if (el) {
        setTimeout(function () {
          el.scrollIntoView({ behavior: 'smooth' });
        }, 100);
      }
    } else {
      switchOS('macos');
    }
  }

  checkHash();
  window.addEventListener('hashchange', checkHash);

  // Category Filters (macOS)
  const catButtons = document.querySelectorAll('.filter-btn');
  const macosCards = document.querySelectorAll('#macos-showcase .app-card');

  catButtons.forEach(function (btn) {
    btn.addEventListener('click', function () {
      catButtons.forEach(function (b) { b.classList.remove('active'); });
      btn.classList.add('active');

      const filter = btn.getAttribute('data-filter');
      macosCards.forEach(function (card) {
        const cats = card.getAttribute('data-category') || '';
        if (filter === 'all' || cats.includes(filter)) {
          card.classList.remove('hidden');
        } else {
          card.classList.add('hidden');
        }
      });
    });
  });

  // Copy SHA-256 Button
  const copyButtons = document.querySelectorAll('.copy-hash-btn');
  copyButtons.forEach(function (btn) {
    btn.addEventListener('click', function () {
      const hash = btn.getAttribute('data-hash');
      if (hash && navigator.clipboard) {
        navigator.clipboard.writeText(hash).then(function () {
          const originalText = btn.textContent;
          btn.textContent = btn.getAttribute('data-copied-text') || 'Kopyalandı!';
          btn.classList.add('copied');
          setTimeout(function () {
            btn.textContent = originalText;
            btn.classList.remove('copied');
          }, 2200);
        });
      }
    });
  });
});
