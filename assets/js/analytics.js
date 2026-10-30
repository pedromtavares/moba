export function initAnalytics() {
  const id = document.querySelector('meta[name="google-analytics-id"]')?.content;
  if (!/^G-[A-Z0-9]+$/.test(id || '') || document.getElementById('google-analytics-script')) return;

  window.dataLayer = window.dataLayer || [];
  window.gtag = function() { window.dataLayer.push(arguments); };
  window.gtag('js', new Date());
  window.gtag('config', id);

  const script = document.createElement('script');
  script.id = 'google-analytics-script';
  script.async = true;
  script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(id)}`;
  document.head.appendChild(script);
}
