// Power Snip! service worker — v13
// Network-first for HTML so shipped fixes reach players immediately;
// cache-first for static assets; cache is the offline fallback.
// v13 (2026-07-17): cache-bust to force devices stuck on an old broken index.html
// (incl. home-screen PWA installs) to discard it — activate() deletes every non-current
// cache, so a stale 20442832-era build can't keep being served.
const C = 'power-snip-v16';
const CORE = ['./', './index.html', './manifest.json'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(C).then((c) => c.addAll(CORE)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => k !== C).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

function isHtml(req) {
  if (req.mode === 'navigate') return true;
  const a = req.headers.get('accept') || '';
  if (a.includes('text/html')) return true;
  const p = new URL(req.url).pathname;
  return p === '/' || p.endsWith('.html');
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const sameOrigin = new URL(req.url).origin === location.origin;

  if (isHtml(req)) {
    e.respondWith(
      fetch(req)
        .then((n) => {
          if (n && n.ok && sameOrigin) {
            const cl = n.clone();
            caches.open(C).then((c) => c.put(req, cl));
          }
          return n;
        })
        .catch(() => caches.match(req).then((r) => r || caches.match('./index.html')))
    );
    return;
  }

  e.respondWith(
    caches.match(req).then(
      (r) =>
        r ||
        fetch(req)
          .then((n) => {
            if (n && n.ok && sameOrigin) {
              const cl = n.clone();
              caches.open(C).then((c) => c.put(req, cl));
            }
            return n;
          })
          .catch(() => caches.match('./index.html'))
    )
  );
});
