(function () {
  'use strict';
  var root = document.getElementById('cm-interaction');
  var label = document.getElementById('cm-interaction-label');
  if (!root || !label) return;

  function hide() {
    root.classList.remove('is-visible');
    root.classList.remove('is-disabled');
    root.setAttribute('aria-hidden', 'true');
  }

  function show(data) {
    data = data || {};
    label.textContent = data.label || 'Interact';
    root.classList.toggle('is-disabled', data.disabled === true);
    root.classList.add('is-visible');
    root.setAttribute('aria-hidden', 'false');
  }

  window.addEventListener('message', function (event) {
    var message = event.data || {};
    if (message.action === 'interaction:show') show(message.data);
    else if (message.action === 'interaction:hide') hide();
  });
}());
