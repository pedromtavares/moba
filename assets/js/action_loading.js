const verbs = {
  'begin-training': 'Preparing',
  create: 'Creating',
  continue: 'Resuming',
  archive: 'Archiving',
  'archive-team': 'Archiving',
  'load-all': 'Loading',
  battle: 'Preparing',
  league: 'Preparing',
  'refresh-targets': 'Searching',
  'show-log': 'Opening',
  'toggle-battle-details': 'Opening',
  buyback: 'Reviving',
  'shard-buyback': 'Reviving',
  restart: 'Restarting',
  'start-farming': 'Starting',
  'finish-farming': 'Collecting',
  'start-edit': 'Opening',
  'finalize-edit': 'Saving',
  'open-shop-item': 'Opening',
  buy: 'Buying',
  sell: 'Selling',
  'start-transmute': 'Preparing',
  'finish-transmute': 'Transmuting',
  matchmaking: 'Matching',
  'season-duel': 'Matching',
  challenge: 'Challenging',
  'set-status': 'Updating',
  start: 'Starting',
  repeat: 'Restoring',
  'new-team': 'Creating',
  'remove-team': 'Deleting',
  'toggle-defensive': 'Saving',
  'next-turn': 'Attacking',
  'next-battle': 'Preparing',
  'auto-battle': 'Starting',
  'auto-match': 'Starting',
  pause: 'Pausing',
  pick: 'Picking',
  accept: 'Joining',
  reject: 'Declining',
  rematch: 'Requesting',
  'create-message': 'Sending',
  'delete-message': 'Deleting',
  'set-featured': 'Saving',
  'unlock-avatar': 'Unlocking',
  'unlock-skin': 'Unlocking',
  send_email: 'Sending',
  send_instructions: 'Sending',
  reset_password: 'Resetting',
  confirm_account: 'Confirming'
};

const controlSelector = 'button, a, input[type="checkbox"], [role="button"], [phx-click]';
const pending = new WeakMap();

function pendingVerb(event, control) {
  switch (event) {
    case 'toggle-combat-log':
      if (control.id.endsWith('combat-log-close')) return 'Closing';
      return control.getAttribute('aria-expanded') === 'true' ? 'Closing' : 'Opening';
    case 'toggle-customize':
      return control.getAttribute('aria-expanded') === 'true' ? 'Closing' : 'Opening';
    case 'toggle-shop':
      return control.classList.contains('active-shop') ? 'Closing' : 'Opening';
    case 'save':
      return control.form?.id === 'registration_form' ? 'Creating' : 'Saving';
    default:
      return Object.hasOwn(verbs, event) ? verbs[event] : null;
  }
}

function showActionLoading(control, verb, complete, compact) {
  const token = {};
  const previous = pending.get(control);
  const busy = previous ? previous.busy : control.getAttribute('aria-busy');
  pending.set(control, {token, busy, blockClick: Boolean(verb)});
  control.dataset.actionLoading = compact ? '' : `${verb}…`;
  control.setAttribute('aria-busy', 'true');

  const clear = () => {
    if (pending.get(control)?.token !== token) return;
    pending.delete(control);
    delete control.dataset.actionLoading;
    if (busy === null) control.removeAttribute('aria-busy');
    else control.setAttribute('aria-busy', busy);
  };
  complete.then(clear, clear);
}

export function initActionLoading() {
  document.addEventListener('phx:push', ({target, detail}) => {
    if (target.closest('.community')) return;
    if (detail.eventType === 'change' && target.matches('select, input[type="range"]')) {
      showActionLoading(target, null, detail.loadingComplete, true);
      return;
    }
    if (!['click', 'submit', 'hook'].includes(detail.eventType)) return;
    if (detail.eventType === 'submit' && !target.matches('form')) return;

    const control = target.matches('form')
      ? detail.loadingElements.find(element => element.form === target && element.matches('.phx-submit-loading'))
        || target.querySelector('button[type="submit"], button:not([type])')
      : detail.eventType === 'hook' && detail.event === 'create'
        ? target.querySelector('#create-button') || target
        : target;
    if (!control?.matches(controlSelector)) return;

    const verb = pendingVerb(detail.event, control);
    if (detail.eventType === 'hook' && !verb && !control.hasAttribute('phx-click')) return;
    const width = control.getBoundingClientRect().width;
    const compact = !verb || (control.id !== 'combat-log-toggle' && width < 72);
    showActionLoading(control, verb, detail.loadingComplete, compact);
  });

  document.addEventListener('click', event => {
    const control = event.target.closest(controlSelector);
    if (!control || !pending.get(control)?.blockClick) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);
}
