/* Shared confirmation component for the Organization Hub design. */
(() => {
  'use strict';
  const ui = window.CMUI = window.CMUI || {};
  let active = null;
  ui.cancelOrganizationConfirm = () => {
    if (!active) return false;
    active.cancel();
    return true;
  };
  ui.confirmOrganizationAction = options => {
    if (active) return Promise.resolve(false);
    const previousFocus = document.activeElement;
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay active cm-confirm-modal';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', options.title || 'Confirm action');
    const escape = ui.safeText;
    overlay.innerHTML = `<div class="modal-box"><div class="modal-header"><h2 class="cm-confirm-modal__title">${escape(options.title || 'CONFIRM ACTION')}</h2></div><p class="cm-confirm-modal__message">${escape(options.message)}</p><p class="cm-confirm-modal__consequence">${escape(options.consequence || '')}</p><p class="cm-confirm-modal__status" role="status"></p><div class="modal-footer cm-confirm-modal__actions"><button type="button" class="btn btn-secondary cm-confirm-modal__cancel">CANCEL</button><button type="button" class="btn ${options.danger ? 'btn-danger' : 'btn-primary'} cm-confirm-modal__confirm">CONFIRM</button></div></div>`;
    document.body.append(overlay);
    const cancel = overlay.querySelector('.cm-confirm-modal__cancel');
    const confirm = overlay.querySelector('.cm-confirm-modal__confirm');
    const status = overlay.querySelector('[role="status"]');
    return new Promise(resolve => {
      let settled = false, busy = false;
      const finish = result => {
        if (settled) return;
        settled = true;
        active = null;
        window.removeEventListener('keydown', onKey, true);
        overlay.remove();
        if (previousFocus?.isConnected && !document.body.hidden) previousFocus.focus();
        resolve(result);
      };
      const cancelAction = () => finish(false);
      const onKey = event => {
        if (event.key === 'Escape') {
          event.preventDefault(); event.stopImmediatePropagation(); cancelAction();
        } else if (event.key === 'Tab') {
          event.preventDefault();
          (document.activeElement === cancel && !busy ? confirm : cancel).focus();
        }
      };
      active = { cancel: cancelAction };
      cancel.onclick = cancelAction;
      overlay.onclick = event => { if (event.target === overlay && !busy) cancelAction(); };
      confirm.onclick = async () => {
        if (busy) return;
        busy = true; confirm.disabled = true; confirm.textContent = 'PROCESSING…';
        status.textContent = 'Waiting for confirmation…';
        try {
          const result = await options.submit();
          if (settled) return;
          if (!result?.ok) throw new Error(result?.error || result?.message || 'The action could not be completed.');
          status.classList.add('is-success');
          status.textContent = result.message || 'Action completed.';
          confirm.textContent = 'SUCCESS';
          setTimeout(() => finish(true), 450);
        } catch (error) {
          if (settled) return;
          status.textContent = error.message;
          status.classList.add('is-error');
          busy = false; confirm.disabled = false; confirm.textContent = 'RETRY';
          cancel.focus();
        }
      };
      window.addEventListener('keydown', onKey, true);
      cancel.focus();
    });
  };
})();
