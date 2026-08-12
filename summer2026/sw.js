/* ============================================================
 * 交大2026暑假服务指南 · Service Worker
 * 策略：Stale-While-Revalidate（缓存先响应+后台更新）
 *       导航请求使用 Network-First（保证 HTML 最新）
 * ============================================================ */
const CACHE_NAME = 'sjtu-summer2026-v1';
const PRECACHE_URLS = [
  './',
  './index.html',
  './calendar.html',
  './manifest.json',
  './icon-192.svg',
  './icon-512.svg',
  './icon-maskable.svg',
  './apple-touch-icon.svg'
];

/* ---------- Install：预缓存资源 ---------- */
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        return cache.addAll(PRECACHE_URLS).catch(() => {
          // 部分资源失败也不阻塞安装
          return Promise.all(
            PRECACHE_URLS.map(url =>
              cache.add(url).catch(() => null)
            )
          );
        });
      })
      .then(() => self.skipWaiting())
  );
});

/* ---------- Activate：清理旧缓存 ---------- */
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

/* ---------- Fetch：SWR + 导航请求 Network First ---------- */
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  // 导航请求：Network First，失败回退到缓存（离线可用）
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((resp) => {
          // 成功则更新缓存
          const clone = resp.clone();
          caches.open(CACHE_NAME).then(c => c.put(req, clone));
          return resp;
        })
        .catch(async () => {
          const cached = await caches.match(req);
          if (cached) return cached;
          // 兜底：缓存的首页
          return caches.match('./index.html');
        })
    );
    return;
  }

  // 其它：Stale-While-Revalidate
  const url = new URL(req.url);
  // 跳过非本站 HTTP(S) 请求（如外部字体 / 外部 OG 图）
  if (url.origin !== self.location.origin) {
    // 对 Google Fonts 等跨域字体做 cache first
    if (req.destination === 'font' || req.destination === 'style') {
      event.respondWith(
        caches.match(req).then((cached) => {
          if (cached) return cached;
          return fetch(req).then((resp) => {
            if (resp.ok) {
              const clone = resp.clone();
              caches.open(CACHE_NAME).then(c => c.put(req, clone));
            }
            return resp;
          }).catch(() => cached);
        })
      );
    }
    return;
  }

  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      const cached = await cache.match(req);
      const fetchPromise = fetch(req).then((resp) => {
        if (resp.ok) cache.put(req, resp.clone());
        return resp;
      }).catch(() => cached || Response.error());
      return cached || fetchPromise;
    })
  );
});

/* ---------- 消息：手动触发更新检查 ---------- */
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
  if (event.data === 'CHECK_VERSION') {
    event.source.postMessage({ type: 'VERSION', name: CACHE_NAME });
  }
});
