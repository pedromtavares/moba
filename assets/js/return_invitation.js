export function initReturnInvitation() {
  const form = document.getElementById('return-invitation-form');
  if (!form) return;
  window.addEventListener('hashchange', () => {
    if (window.location.hash) window.location.reload();
  });
  if (form.dataset.invalid === 'true') return;

  const token = new URLSearchParams(window.location.hash.slice(1)).get('token');
  window.history.replaceState(null, '', window.location.pathname);

  const button = document.getElementById('return-enter');
  const input = document.getElementById('return-token');
  const heading = document.getElementById('return-heading');
  const description = document.getElementById('return-description');
  const status = document.getElementById('return-status');
  const login = document.getElementById('return-login');

  const unavailable = (networkError = false) => {
    input.value = '';
    form.hidden = true;
    login.hidden = false;
    status.hidden = true;
    heading.textContent = networkError ? 'Your heroes are waiting.' : 'Your invitation has expired.';
    description.textContent = networkError
      ? 'We couldn’t open your invitation. Try the email link again, or sign in.'
      : 'This link may have already been used. Sign in to return to your heroes.';
  };

  form.addEventListener('submit', () => {
    button.disabled = true;
    button.textContent = 'Entering…';
  });

  if (!/^[A-Za-z0-9_-]{43}$/.test(token || '')) {
    unavailable();
    return;
  }

  fetch(form.dataset.checkUrl, {
    method: 'POST',
    credentials: 'same-origin',
    cache: 'no-store',
    headers: {
      'content-type': 'application/json',
      'x-csrf-token': document.querySelector('meta[name="csrf-token"]').content
    },
    body: JSON.stringify({token})
  }).then(async response => {
    if (!response.ok) {
      unavailable(response.status >= 500);
      return;
    }
    const {username} = await response.json();
    heading.textContent = `Welcome back, ${username}.`;
    input.value = token;
    button.disabled = false;
    status.hidden = true;
  }).catch(() => unavailable(true));
}
