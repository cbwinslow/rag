// Module Worker - supports env bindings via `env` parameter
export default {
  async fetch(request, env) {
    const url = new URL(request.url)

    // RAG Service Routes
    if (url.pathname.startsWith('/v1/chat')) {
      return handleProxyRequest(request, env.RAG_SERVICE_URL);
    }
    
    if (url.pathname.startsWith('/v1/ingest')) {
      return handleProxyRequest(request, env.INGESTOR_SERVICE_URL);
    }

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

    // Route: /supabase/store - Store documents in Supabase tables
    if (url.pathname === '/supabase/store' && request.method === 'POST') {
      const apiKey = env && env.AUTORAG_API_KEY ? env.AUTORAG_API_KEY : url.searchParams.get('api_key')
      if (!apiKey) return new Response('api_key required', { status: 401 })
      if (env && env.AUTORAG_API_KEY && apiKey !== env.AUTORAG_API_KEY) return new Response('invalid api_key', { status: 403 })

      if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
        return new Response('Supabase configuration missing', { status: 500 })
      }

      const text = await request.text()
      let stored = 0
      let errors = []

      for (const line of text.split('\n')) {
        if (!line.trim()) continue
        try {
          const doc = JSON.parse(line)
          // Store in Supabase documents table
          const supabaseResponse = await fetch(`${env.SUPABASE_URL}/rest/v1/documents`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${env.SUPABASE_ANON_KEY}`,
              'apikey': env.SUPABASE_ANON_KEY
            },
            body: JSON.stringify({
              url: doc.url,
              title: doc.title,
              content: doc.content,
              source: doc.source,
              date: doc.date,
              metadata: doc.metadata || {}
            })
          })

          if (supabaseResponse.ok) {
            stored++
          } else {
            errors.push(`Failed to store ${doc.url}: ${supabaseResponse.status}`)
          }
        } catch (e) {
          errors.push(`Parse error: ${e.message}`)
        }
      }

      return new Response(JSON.stringify({ stored, errors }), {
        headers: { 'content-type': 'application/json' }
      })
    }

    // Route: /supabase/search - Search documents in Supabase
    if (url.pathname === '/supabase/search') {
      if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
        return new Response('Supabase configuration missing', { status: 500 })
      }

      const query = url.searchParams.get('q')
      if (!query) return new Response('query parameter required', { status: 400 })

      const supabaseResponse = await fetch(
        `${env.SUPABASE_URL}/rest/v1/documents?content=ilike.*${encodeURIComponent(query)}*&select=*`,
        {
          headers: {
            'Authorization': `Bearer ${env.SUPABASE_ANON_KEY}`,
            'apikey': env.SUPABASE_ANON_KEY
          }
        }
      )

      if (!supabaseResponse.ok) {
        return new Response('Search failed', { status: supabaseResponse.status })
      }

      const results = await supabaseResponse.json()
      return new Response(JSON.stringify(results), {
        headers: { 'content-type': 'application/json' }
      })
    }

    // Route: /kv/list - list keys (admin/debug) - restricted by env.AUTH or similar in production
    if (url.pathname === '/kv/list') {
      // limit exposure: require AUTORAG_API_KEY
      const apiKey = env && env.AUTORAG_API_KEY ? env.AUTORAG_API_KEY : url.searchParams.get('api_key')
      if (!apiKey || (env && env.AUTORAG_API_KEY && apiKey !== env.AUTORAG_API_KEY)) return new Response('forbidden', { status: 403 })
      const list = await env.AUTORAG_KV.list({ limit: 100 })
      return new Response(JSON.stringify(list), { headers: { 'content-type': 'application/json' } })
    }

    return new Response('RAG Cloudflare Worker: use /fetch, /govinfo, /congress, /supabase/store, /supabase/search', { status: 200 })
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
