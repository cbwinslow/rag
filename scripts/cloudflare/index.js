// Module Worker - supports env bindings via `env` parameter
function safeLog(...args) {
  if (typeof console !== 'undefined' && typeof console.debug === 'function') {
    console.debug(...args)
  }
}

// Helper: parse a single NDJSON line into a document or an error/skip marker
export function parseJSONLine(line) {
  if (!line || !line.trim()) return { skipped: true }
  try {
    const doc = JSON.parse(line)
    return { doc }
  } catch (e) {
    return { error: `Parse error: ${e && e.message ? e.message : String(e)}` }
  }
}

// Exported helper: insert a document into Supabase via REST; accepts env to make testing possible
export async function insertDocToSupabase(doc, env) {
  try {
    const resp = await fetch(`${env.SUPABASE_URL}/rest/v1/documents`, {
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
    if (resp && resp.ok) return { ok: true }
    return { error: `Failed to store ${doc && doc.url ? doc.url : '<unknown>'}: ${resp.status}` }
  } catch (e) {
    safeLog('insertDocToSupabase error', e && e.message ? e.message : String(e))
    return { error: `Upstream error: ${e && e.message ? e.message : String(e)}` }
  }
}

async function handleProxyIfNeeded(request, env, url) {
  if (url.pathname.startsWith('/v1/chat')) return handleProxyRequest(request, env.RAG_SERVICE_URL)
  if (url.pathname.startsWith('/v1/ingest')) return handleProxyRequest(request, env.INGESTOR_SERVICE_URL)
  return null
}

async function handleFetchRoute(request, env, url) {
  const path = url.searchParams.get('path') || '/'
  const target = `https://opendiscourse.net${path}`
  return fetchAndCache(request, target)
}

async function handleGovinfoRoute(request, env, url) {
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
  // Prefer APP_ prefixed env name for consistency with repo convention; fall back for backwards compatibility
  const apiKey = env && (env.APP_GOVINFO_API_KEY || env.GOVINFO_API_KEY) ? (env.APP_GOVINFO_API_KEY || env.GOVINFO_API_KEY) : url.searchParams.get('api_key')
  if (apiKey) target += (target.includes('?') ? '&' : '?') + `api_key=${encodeURIComponent(apiKey)}`
  return fetchAndCache(request, target, { headers: { Accept: 'application/json' } })
}

async function handleCongressRoute(request, env, url) {
  const path = url.searchParams.get('path') || '/'
  const target = `https://www.congress.gov${path}`
  return fetchAndCache(request, target)
}

async function handleStore(request, env) {
  const apiKey = env && (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) ? (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) : new URL(request.url).searchParams.get('api_key')
  if (!apiKey) return new Response('api_key required', { status: 401 })
  if (env && (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) && apiKey !== (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY)) return new Response('invalid api_key', { status: 403 })
  if (!env || !env.AUTORAG_KV) return new Response('KV binding not configured', { status: 500 })
  const text = await request.text()
  let count = 0
  for (const line of text.split('\n')) {
    if (!line) continue
    try {
      const obj = JSON.parse(line)
      const id = obj.url || ('doc-' + Math.random().toString(36).slice(2, 12))
      await env.AUTORAG_KV.put(id, JSON.stringify(obj))
      count += 1
    } catch (e) {
      safeLog('store: parse error for line', e && e.message ? e.message : String(e))
    }
  }
  return new Response(JSON.stringify({ stored: count }), { headers: { 'content-type': 'application/json' } })
}

async function handleSupabaseStore(request, env) {
  const apiKey = env && (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) ? (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) : new URL(request.url).searchParams.get('api_key')
  if (!apiKey) return new Response('api_key required', { status: 401 })
  if (env && (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) && apiKey !== (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY)) return new Response('invalid api_key', { status: 403 })
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return new Response('Supabase configuration missing', { status: 500 })

  // Small helper: parse a single NDJSON line into a document or an error object
  // Use the exported helpers above (parseJSONLine and insertDocToSupabase)

  const text = await request.text()
  let stored = 0
  const errors = []

  for (const line of text.split('\n')) {
  const parsed = parseJSONLine(line)
    if (!parsed) continue
    if (parsed.skipped) continue
    if (parsed.error) {
      errors.push(parsed.error)
      continue
    }
  const res = await insertDocToSupabase(parsed.doc, env)
    if (res.ok) stored++
    else if (res.error) errors.push(res.error)
  }

  return new Response(JSON.stringify({ stored, errors }), { headers: { 'content-type': 'application/json' } })
}

async function handleSupabaseSearch(request, env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return new Response('Supabase configuration missing', { status: 500 })
  const url = new URL(request.url)
  const query = url.searchParams.get('q')
  if (!query) return new Response('query parameter required', { status: 400 })
  const supabaseResponse = await fetch(
    `${env.SUPABASE_URL}/rest/v1/documents?content=ilike.*${encodeURIComponent(query)}*&select=*`,
    { headers: { 'Authorization': `Bearer ${env.SUPABASE_ANON_KEY}`, 'apikey': env.SUPABASE_ANON_KEY } }
  )
  if (!supabaseResponse.ok) return new Response('Search failed', { status: supabaseResponse.status })
  const results = await supabaseResponse.json()
  return new Response(JSON.stringify(results), { headers: { 'content-type': 'application/json' } })
}

async function handleKVList(request, env) {
  const apiKey = env && (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) ? (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) : new URL(request.url).searchParams.get('api_key')
  if (!apiKey || (env && (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY) && apiKey !== (env.APP_AUTORAG_API_KEY || env.AUTORAG_API_KEY))) return new Response('forbidden', { status: 403 })
  if (!env || !env.AUTORAG_KV) return new Response('KV binding not configured', { status: 500 })
  const list = await env.AUTORAG_KV.list({ limit: 100 })
  return new Response(JSON.stringify(list), { headers: { 'content-type': 'application/json' } })
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
    // Avoid exposing internal error structure; return a simple upstream-failed response
    const msg = e && e.message ? e.message : String(e)
    safeLog('fetchAndCache upstream fetch failed', msg)
    return new Response('Upstream fetch failed', { status: 502 })
  }
  if (resp && resp.status >= 200 && resp.status < 400) {
    const clone = resp.clone()
    // event isn't available here; use background put
    cache.put(cacheKey, clone).catch(() => {})
  }
  return resp
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url)

    // proxy short-circuits
    const proxied = await handleProxyIfNeeded(request, env, url)
    if (proxied) return proxied

    // Route: /fetch?path=/path -> opendiscourse
    if (url.pathname === '/fetch') return handleFetchRoute(request, env, url)

    // Route: /govinfo?type=api|bulk
    if (url.pathname === '/govinfo') return handleGovinfoRoute(request, env, url)

    // Route: /congress?path=/search
    if (url.pathname === '/congress') return handleCongressRoute(request, env, url)

    // Route: /store - accept POST NDJSON and store into KV (requires AUTORAG_API_KEY to be set in env or passed as api_key)
    if (url.pathname === '/store' && request.method === 'POST') return handleStore(request, env)

    // Route: /supabase/store - Store documents in Supabase tables
    if (url.pathname === '/supabase/store' && request.method === 'POST') return handleSupabaseStore(request, env)

    // Route: /supabase/search - Search documents in Supabase
    if (url.pathname === '/supabase/search') return handleSupabaseSearch(request, env)

    // Route: /kv/list - list keys (admin/debug) - restricted by env.AUTH or similar in production
    if (url.pathname === '/kv/list') return handleKVList(request, env)

    return new Response('RAG Cloudflare Worker: use /fetch, /govinfo, /congress, /supabase/store, /supabase/search', { status: 200 })
  }
}
