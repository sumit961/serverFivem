/* ============================================================================
   CM ORGANIZATION DASHBOARD — client-side filters  (cm-ems / cm-law / cm-police)
   ----------------------------------------------------------------------------
   Adds a search box above the member roster and the activity log.

   Deliberately standalone: it does not touch app.js in any of the three
   resources. It finds the list containers by id, injects a control bar, and
   hides non-matching rows with a class. app.js is free to re-render those
   lists whenever it likes -- a MutationObserver re-applies the active filter
   afterwards, so a promote/demote refresh does not wipe the search.

   Container ids differ per resource, hence the lists below:
     cm-ems / cm-police   #members  #logs
     cm-law               #roster   #activityLogList

   Filtering is presentation only. It never changes what the server sent, and
   it cannot reveal a row the player was not already allowed to see -- the
   logs page is still gated by the view-logs permission server-side.
   ========================================================================== */

(function () {
  'use strict';

  var HIDDEN = 'cc-filter-hidden';

  // [containerId, placeholder, rowSelector, label]
  var TARGETS = [
    ['members', 'Search name, CID or rank', '.member, .list-row', 'roster'],
    ['roster', 'Search name, CID or rank', '.member, .list-row', 'roster'],
    ['logs', 'Search member, action or detail', '.log-row', 'log'],
    ['activityLogList', 'Search member, action or detail', '.log-row', 'log']
  ];

  function normalise(text) {
    return (text || '').toLowerCase().replace(/\s+/g, ' ').trim();
  }

  function applyFilter(container, query) {
    var rows = container.querySelectorAll(container.__ccRowSelector);
    var term = normalise(query);
    var shown = 0;

    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      // Cache the row's searchable text so repeated keystrokes don't re-read
      // the DOM. Invalidated by the observer whenever app.js re-renders.
      if (row.__ccText === undefined) row.__ccText = normalise(row.textContent);
      var match = term === '' || row.__ccText.indexOf(term) !== -1;
      row.classList.toggle(HIDDEN, !match);
      if (match) shown++;
    }

    if (container.__ccCount) {
      container.__ccCount.textContent = term === ''
        ? shown + (shown === 1 ? ' entry' : ' entries')
        : shown + ' of ' + rows.length + ' shown';
    }

    if (container.__ccEmpty) {
      container.__ccEmpty.classList.toggle(HIDDEN, !(rows.length > 0 && shown === 0));
    }
  }

  function buildBar(container, placeholder) {
    var bar = document.createElement('div');
    bar.className = 'cc-filterbar';

    var input = document.createElement('input');
    input.type = 'search';
    input.className = 'cc-filterbar__input';
    input.placeholder = placeholder;
    input.setAttribute('aria-label', placeholder);
    input.autocomplete = 'off';
    // NUI keeps focus on the page, so a stray keystroke must not fire a
    // gameplay keybind while the player is typing here.
    input.addEventListener('keydown', function (event) { event.stopPropagation(); });

    var count = document.createElement('span');
    count.className = 'cc-filterbar__count';

    var clear = document.createElement('button');
    clear.type = 'button';
    clear.className = 'cc-filterbar__clear';
    clear.textContent = 'Clear';
    clear.addEventListener('click', function () {
      input.value = '';
      applyFilter(container, '');
      input.focus();
    });

    input.addEventListener('input', function () {
      applyFilter(container, input.value);
    });

    bar.appendChild(input);
    bar.appendChild(count);
    bar.appendChild(clear);

    var empty = document.createElement('p');
    empty.className = 'cc-filter-empty ' + HIDDEN;
    empty.textContent = 'Nothing matches that search.';

    container.__ccInput = input;
    container.__ccCount = count;
    container.__ccEmpty = empty;

    container.parentNode.insertBefore(bar, container);
    container.parentNode.insertBefore(empty, container.nextSibling);
  }

  function attach(id, placeholder, rowSelector) {
    var container = document.getElementById(id);
    if (!container || container.__ccFiltered) return;

    container.__ccFiltered = true;
    container.__ccRowSelector = rowSelector;
    buildBar(container, placeholder);

    // app.js replaces innerHTML on refresh, which drops our cached row text and
    // the hidden class. Re-apply whatever is currently typed.
    var observer = new MutationObserver(function () {
      var rows = container.querySelectorAll(rowSelector);
      for (var i = 0; i < rows.length; i++) rows[i].__ccText = undefined;
      applyFilter(container, container.__ccInput.value);
    });
    observer.observe(container, { childList: true });

    applyFilter(container, '');
  }

  function init() {
    for (var i = 0; i < TARGETS.length; i++) {
      attach(TARGETS[i][0], TARGETS[i][1], TARGETS[i][2]);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
