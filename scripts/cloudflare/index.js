// Module Worker - supports env bindings via `env` parameter
export default {
  async fetch(request, env) {
    const url = new URL(request.url)

    // Route: /fetch?path=/path -> opendiscourse
    if (url.pathname === '/fetch') {
      const path = url.searchParams.get('path') || '/'
      const target = `https://opendiscourse.net${path}`
      return fetchAndCache(request, target)
    }

    // Route: /govinfo?type=api|bulk
    if (url.pathname === '/govinfo') {
      const type = url.searchParams.get('type') || 'api'
      if (type === 'bulk') {
        const bulkUrl = url.searchParams.get('url')
        if (!bulkUrl) return new Response('missing url parameter', { status: 400 })
        return fetchAndCache(request, bulkUrl)
      }
      const apiPath = url.searchParams.get('path') || '/'
      const q = url.searchParams.get('query') || ''
      let target = 'https://api.govinfo.gov' + apiPath
      if (q) target += (target.includes('?') ? '&' : '?') + `query=${encodeURIComponent(q)}`
      // prefer secret-bound API key (env.GOVINFO_API_KEY) over query param
      const apiKey = env && env.GOVINFO_API_KEY ? env.GOVINFO_API_KEY : url.searchParams.get('api_key')
      if (apiKey) target += (target.includes('?') ? '&' : '?') + `api_key=${encodeURIComponent(apiKey)}`
      return fetchAndCache(request, target, { headers: { Accept: 'application/json' } })
    }

    // Route: /congress?path=/search
    if (url.pathname === '/congress') {
      const path = url.searchParams.get('path') || '/'
      const target = `https://www.congress.gov${path}`
      return fetchAndCache(request, target)
    }

    // Route: /store - accept POST NDJSON and store into KV (requires AUTORAG_API_KEY to be set in env or passed as api_key)
    if (url.pathname === '/store' && request.method === 'POST') {
      const apiKey = env && env.AUTORAG_API_KEY ? env.AUTORAG_API_KEY : url.searchParams.get('api_key')
      if (!apiKey) return new Response('api_key required', { status: 401 })
      // In production validate apiKey matches expected secret (compare to env.AUTORAG_API_KEY if set)
      if (env && env.AUTORAG_API_KEY && apiKey !== env.AUTORAG_API_KEY) return new Response('invalid api_key', { status: 403 })
      const text = await request.text()
      // expect NDJSON
      let count = 0
      for (const line of text.split('\n')) {
        if (!line) continue
        try {
          const obj = JSON.parse(line)
          const id = obj.url || ('doc-' + Math.random().toString(36).slice(2,12))
          // store in KV namespace AUTORAG_KV
          await env.AUTORAG_KV.put(id, JSON.stringify(obj))
          count += 1
        } catch (e) {
          // ignore parse errors
        }
      }
      return new Response(JSON.stringify({ stored: count }), { headers: { 'content-type': 'application/json' } })
    }

    // Route: /kv/list - list keys (admin/debug) - restricted by env.AUTH or similar in production
    if (url.pathname === '/kv/list') {
      // limit exposure: require AUTORAG_API_KEY
      const apiKey = env && env.AUTORAG_API_KEY ? env.AUTORAG_API_KEY : url.searchParams.get('api_key')
      if (!apiKey || (env && env.AUTORAG_API_KEY && apiKey !== env.AUTORAG_API_KEY)) return new Response('forbidden', { status: 403 })
      const list = await env.AUTORAG_KV.list({ limit: 100 })
      return new Response(JSON.stringify(list), { headers: { 'content-type': 'application/json' } })
    }

    return new Response('RAG Cloudflare Worker: use /fetch, /govinfo or /congress', { status: 200 })
  }
}

async function fetchAndCache(request, targetUrl, opts = {}) {
  const cache = caches.default
  const cacheKey = new Request(targetUrl)
  let resp = await cache.match(cacheKey)
  if (resp) return resp
  let init = opts || {}
  init.cf = init.cf || { scrapeShield: true }
  try {
    resp = await fetch(targetUrl, init)
  } catch (e) {
    return new Response('Upstream fetch failed: ' + e.message, { status: 502 })
  }
  if (resp && resp.status >= 200 && resp.status < 400) {
    const clone = resp.clone()
    // event isn't available here; use waitUntil on a new Response? use background put
    cache.put(cacheKey, clone).catch(() => {})
  }
  return resp
}
