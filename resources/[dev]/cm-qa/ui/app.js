const root = document.getElementById('qa-root');
const title = document.getElementById('title');
const bodyText = document.getElementById('body');
const hint = document.getElementById('hint');

function resetQaUi() {
  root.className = 'hidden';
  root.removeAttribute('style');
  root.removeAttribute('data-scenario');
  root.setAttribute('aria-hidden', 'true');
  title.textContent = '';
  bodyText.textContent = '';
  hint.textContent = '';
  root.querySelectorAll('[data-qa-progress], [data-qa-overlay]').forEach((node) => node.remove());
  root.querySelectorAll('[style]').forEach((node) => node.removeAttribute('style'));
  document.documentElement.classList.remove('qa-active');
  document.body.classList.remove('qa-active');
  document.documentElement.style.removeProperty('background');
  document.documentElement.style.removeProperty('background-color');
  document.body.style.removeProperty('background');
  document.body.style.removeProperty('background-color');
}

function openQaUi(data) {
  root.className = '';
  root.removeAttribute('style');
  root.dataset.scenario = data.scenario || '';
  title.textContent = data.title || 'CM-QA';
  bodyText.textContent = data.body || 'Press ESC to cancel this QA test.';
  hint.textContent = data.hint || 'ESC · cancel';
  root.setAttribute('aria-hidden', 'false');
}

resetQaUi();
window.addEventListener('message', (event) => {
  if (event.data?.action === 'qaOpen') openQaUi(event.data);
  if (event.data?.action === 'qaReset') resetQaUi();
});

document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape' || root.classList.contains('hidden')) return;
  event.preventDefault();
  fetch(`https://${GetParentResourceName()}/cmQaClose`, { method: 'POST', body: '{}' });
});
