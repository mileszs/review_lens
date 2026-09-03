// PR Reviewer Metrics Dashboard - Interactive behaviors
// ~150 lines of vanilla JS, no dependencies

(function() {
  'use strict';

  // 1. TOC active-section highlighting via IntersectionObserver
  function setupTocHighlighting() {
    const sections = document.querySelectorAll('section.section, header.hero');
    if (sections.length === 0) return;

    const observer = new IntersectionObserver((entries) => {
      const visible = entries
        .filter(e => e.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio);

      if (visible.length > 0) {
        document.querySelectorAll('.toc__list a').forEach(a => a.classList.remove('active'));
        const activeLink = document.querySelector(`.toc__list a[href="#${visible[0].target.id}"]`);
        if (activeLink) activeLink.classList.add('active');
      }
    }, { rootMargin: '-30% 0px -60% 0px', threshold: [0, 0.25, 0.5, 1] });

    sections.forEach(s => observer.observe(s));
  }

  // 2. Sortable tables (master table and any .sortable-table)
  const tableSortState = new Map();

  function setupTableSorting() {
    const tables = document.querySelectorAll('.master-table, .sortable-table');

    tables.forEach(table => {
      const tableId = table.id || 'master';
      tableSortState.set(tableId, { key: 'total', dir: 'desc' });

      const headers = table.querySelectorAll('th[data-sort-key]');
      headers.forEach(th => {
        th.style.cursor = 'pointer';
        th.addEventListener('click', () => {
          const key = th.dataset.sortKey;
          const state = tableSortState.get(tableId);

          // Toggle direction if same column, otherwise default to desc
          if (state.key === key) {
            state.dir = state.dir === 'asc' ? 'desc' : 'asc';
          } else {
            state.key = key;
            state.dir = 'desc';
          }

          sortTable(table, key, state.dir);
          updateSortIndicators(headers, th, state.dir);
        });
      });
    });
  }

  function sortTable(table, key, dir) {
    const tbody = table.querySelector('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr[data-row]'));

    rows.sort((a, b) => {
      const aVal = parseValue(a.dataset[key]);
      const bVal = parseValue(b.dataset[key]);

      // Nulls sort to bottom
      if (aVal === null && bVal === null) return 0;
      if (aVal === null) return 1;
      if (bVal === null) return -1;

      const cmp = aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
      return dir === 'asc' ? cmp : -cmp;
    });

    // Re-append rows in sorted order (also moves associated expanded rows)
    rows.forEach(row => {
      tbody.appendChild(row);
      const expandedRow = row.nextElementSibling;
      if (expandedRow && expandedRow.classList.contains('exp-row')) {
        tbody.appendChild(expandedRow);
      }
    });
  }

  function parseValue(val) {
    if (val === undefined || val === '' || val === 'null') return null;
    const num = parseFloat(val);
    return isNaN(num) ? val : num;
  }

  function updateSortIndicators(headers, activeHeader, dir) {
    headers.forEach(th => {
      const btn = th.querySelector('.sort-btn');
      if (btn) {
        btn.textContent = th === activeHeader ? (dir === 'asc' ? '↑' : '↓') : '↕';
      }
    });
  }

  // 3. Search filter
  function setupSearch() {
    const input = document.querySelector('.search-input');
    if (!input) return;

    input.addEventListener('input', () => {
      const q = input.value.trim().toLowerCase();
      document.querySelectorAll('tr[data-row]').forEach(tr => {
        const name = tr.dataset.name || '';
        const matchesSearch = !q || name.toLowerCase().includes(q);
        const matchesFilters = checkFilters(tr);
        tr.hidden = !matchesSearch || !matchesFilters;

        // Also hide/show expanded row
        const expandedRow = tr.nextElementSibling;
        if (expandedRow && expandedRow.classList.contains('exp-row')) {
          expandedRow.hidden = tr.hidden || !tr.classList.contains('exp');
        }
      });
      updateVisibleCount();
    });
  }

  // 4. "Flagged only" toggle
  function setupFlaggedToggle() {
    const checkbox = document.querySelector('#flagged-only');
    if (!checkbox) return;

    checkbox.addEventListener('change', applyFilters);
  }

  // 5. "Hide bots" toggle
  function setupBotToggle() {
    const checkbox = document.querySelector('#hide-bots');
    if (!checkbox) return;

    checkbox.addEventListener('change', applyFilters);
  }

  function checkFilters(tr) {
    const flaggedOnly = document.querySelector('#flagged-only')?.checked;
    const hideBots = document.querySelector('#hide-bots')?.checked;

    if (hideBots && tr.dataset.bot === 'true') return false;
    if (flaggedOnly && tr.dataset.flagged !== 'true') return false;

    return true;
  }

  function applyFilters() {
    const searchInput = document.querySelector('.search-input');
    const q = searchInput ? searchInput.value.trim().toLowerCase() : '';

    document.querySelectorAll('tr[data-row]').forEach(tr => {
      const name = tr.dataset.name || '';
      const matchesSearch = !q || name.toLowerCase().includes(q);
      const matchesFilters = checkFilters(tr);
      tr.hidden = !matchesSearch || !matchesFilters;

      // Also hide expanded row if main row is hidden
      const expandedRow = tr.nextElementSibling;
      if (expandedRow && expandedRow.classList.contains('exp-row')) {
        expandedRow.hidden = tr.hidden || !tr.classList.contains('exp');
      }
    });
    updateVisibleCount();
  }

  function updateVisibleCount() {
    const countEl = document.querySelector('.filter-count');
    if (!countEl) return;

    const visible = document.querySelectorAll('tr[data-row]:not([hidden])').length;
    const total = document.querySelectorAll('tr[data-row]').length;
    countEl.textContent = `${visible} of ${total}`;
  }

  // 6. Row expand/collapse on click
  function setupRowExpand() {
    document.querySelectorAll('tr[data-row]').forEach(tr => {
      tr.addEventListener('click', (e) => {
        // Don't toggle if clicking a link
        if (e.target.tagName === 'A') return;

        const expandedRow = tr.nextElementSibling;
        if (!expandedRow || !expandedRow.classList.contains('exp-row')) return;

        // Close all other expanded rows
        document.querySelectorAll('.exp-row').forEach(r => {
          if (r !== expandedRow) r.hidden = true;
        });
        document.querySelectorAll('tr[data-row]').forEach(r => {
          if (r !== tr) r.classList.remove('exp');
        });

        // Toggle this row
        expandedRow.hidden = !expandedRow.hidden;
        tr.classList.toggle('exp', !expandedRow.hidden);
      });
    });
  }

  // Initialize all behaviors on DOMContentLoaded
  document.addEventListener('DOMContentLoaded', () => {
    setupTocHighlighting();
    setupTableSorting();
    setupSearch();
    setupFlaggedToggle();
    setupBotToggle();
    setupRowExpand();
    updateVisibleCount();

    // Apply initial bot filter if checked
    applyFilters();
  });
})();
