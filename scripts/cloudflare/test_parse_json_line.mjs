import assert from 'assert'
import { parseJSONLine } from './index.js'

// happy path
const input = JSON.stringify({ url: 'https://example.org/doc', title: 'T', content: 'C' })
const res = parseJSONLine(input)
assert(res.doc && res.doc.url === 'https://example.org/doc')

// empty line
assert(parseJSONLine('   ').skipped === true)

// invalid json
const bad = '{not: json}'
const r2 = parseJSONLine(bad)
assert(r2.error && r2.error.startsWith('Parse error'))

console.log('parseJSONLine tests passed')
