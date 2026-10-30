// Keep confirmations in the HUD while preserving Phoenix's original click action.
export function initGameConfirmations() {
  let dialog;
  let pending;
  let returnFocus;

  function close() {
    pending = null;
    dialog.close();
    if (returnFocus?.isConnected) returnFocus.focus();
  }

  document.addEventListener('click', event => {
    const target = event.target.closest('[data-confirm]');
    if (!target?.closest('.game-page')) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    if (!dialog) {
      dialog = document.createElement('dialog');
      dialog.className = 'game-confirm-dialog';
      dialog.id = 'game-confirm-dialog';
      dialog.setAttribute('aria-labelledby', 'game-confirm-title');
      dialog.setAttribute('aria-describedby', 'game-confirm-message');
      dialog.innerHTML = `<span class="game-confirm-mark" aria-hidden="true">!</span>
        <h2 id="game-confirm-title">Confirm action</h2>
        <p id="game-confirm-message"></p>
        <div class="game-confirm-actions">
          <button type="button" id="game-confirm-cancel" autofocus>Cancel</button>
          <button type="button" id="game-confirm-accept">Confirm</button>
        </div>`;
      document.body.appendChild(dialog);
      dialog.querySelector('#game-confirm-cancel').addEventListener('click', close);
      dialog.querySelector('#game-confirm-accept').addEventListener('click', () => {
        const original = pending;
        close();
        if (!original?.isConnected) return;
        const message = original.getAttribute('data-confirm');
        original.removeAttribute('data-confirm');
        original.click();
        original.setAttribute('data-confirm', message);
      });
      dialog.addEventListener('cancel', event => { event.preventDefault(); close(); });
      dialog.addEventListener('click', event => { if (event.target === dialog) close(); });
      dialog.addEventListener('keydown', event => event.stopPropagation());
      window.addEventListener('phx:page-loading-start', () => { if (dialog.open) close(); });
    }
    pending = target;
    returnFocus = document.activeElement;
    dialog.querySelector('#game-confirm-title').textContent = target.dataset.confirmTitle || 'Confirm action';
    dialog.querySelector('#game-confirm-message').textContent = target.dataset.confirm;
    dialog.querySelector('#game-confirm-accept').textContent = target.dataset.confirmAccept || 'Confirm';
    if (!dialog.open) dialog.showModal();
    dialog.querySelector('#game-confirm-cancel').focus();
  }, true);
}

export function isGameTooltip(reference) {
  return !!reference.closest('.game-page');
}

export function tooltipContent(reference, title) {
  if (!isGameTooltip(reference)) return title;
  const content = document.createElement('div');
  content.className = 'game-tooltip-content';
  content.innerHTML = title || '';
  content.querySelectorAll('.badge').forEach(badge => {
    if (!/^\d+$/.test(badge.textContent.trim())) return;
    if (badge.querySelector('.fa-bolt')) badge.append(' Energy');
    if (badge.querySelector('.fa-clock')) badge.append(badge.textContent.trim() === '1' ? ' turn' : ' turns');
  });
  content.querySelectorAll('.game-stat[title]').forEach(stat => {
    const label = document.createElement('small');
    label.className = 'game-tooltip-stat-label';
    label.textContent = stat.getAttribute('title');
    stat.appendChild(label);
  });
  return content.outerHTML;
}
