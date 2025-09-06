import assert from 'assert'
import { insertDocToSupabase } from './index.js'

// Mock env and global fetch
const calls = []
const mockFetch = async (url, opts) => {
  calls.push({ url, opts })
  // Simulate success when body contains a url field
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
  SUPABASE_ANON_KEY: 'anon-key-123'
}

async function runTests() {
  // Happy path
  const doc = { url: 'http://example.com/page', title: 't', content: 'c' }
  const res = await insertDocToSupabase(doc, env)
  assert.strictEqual(res.ok, true, 'expected ok on happy path')

  // Failure path
  const bad = { url: 'not-a-url' }
  const res2 = await insertDocToSupabase(bad, env)
  assert.ok(res2.error, 'expected error for bad doc')

  // Ensure fetch was called
  assert.ok(calls.length >= 2, 'expected at least two fetch calls')

  console.log('insertDocToSupabase tests passed')
}

runTests().then(() => {
  globalThis.fetch = originalFetch
}).catch((e) => {
  globalThis.fetch = originalFetch
  console.error(e)
  process.exit(1)
})
