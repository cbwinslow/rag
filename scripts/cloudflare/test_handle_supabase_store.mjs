import assert from 'assert'
import { parseJSONLine, insertDocToSupabase } from './index.js'

// Mock fetch to capture calls and simulate Supabase
const calls = []
const mockFetch = async (url, opts) => {
  calls.push({ url, opts })
  const body = JSON.parse(opts.body)
  if (body && body.url && body.url.startsWith('http')) {
    return { ok: true, status: 201, json: async () => ({}) }
  }
  return { ok: false, status: 400, json: async () => ({ error: 'bad' }) }
}
const originalFetch = globalThis.fetch
globalThis.fetch = mockFetch

const env = {
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key-123',
  AUTORAG_API_KEY: 'my-api-key'
}

async function run() {
  const ndjson = [
    JSON.stringify({ url: 'http://ok.example/doc1', title: 'Doc1', content: 'x' }),
    '',
    'not-a-json',
    JSON.stringify({ url: 'http://ok.example/doc2', title: 'Doc2', content: 'y' })
  ].join('\n')

  const lines = ndjson.split('\n')
  let stored = 0
  const errors = []
  for (const line of lines) {
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

  // Assertions
  assert.strictEqual(stored, 2, 'expected two stored docs')
  assert.ok(errors.length >= 1, 'expected at least one error due to invalid JSON')
  assert.ok(calls.length >= 2, 'expected supabase fetch called for successful docs')

  console.log('handle_supabase_store integration test passed')
}

run().then(() => { globalThis.fetch = originalFetch }).catch((e) => { globalThis.fetch = originalFetch; console.error(e); process.exit(1) })
