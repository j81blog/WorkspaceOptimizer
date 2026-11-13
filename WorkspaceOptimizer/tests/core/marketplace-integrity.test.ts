import { describe, it, expect, afterEach, vi } from 'vitest'

const INDEX = 'https://cdn.example.com/cat/index.json'
const XML = '<Items>\n  <Item/>\n</Items>\n'

async function load(trustedHosts = 'cdn.example.com') {
  vi.resetModules()
  vi.stubEnv('VITE_MARKETPLACE_URL', INDEX)
  vi.stubEnv('VITE_MARKETPLACE_TRUSTED_HOSTS', trustedHosts)
  return await import('../../src/core/marketplace')
}

/** Response with a settable final URL, which `new Response` cannot do. */
function respond(body: string, finalUrl = '') {
  const res = new Response(body, { status: 200 })
  Object.defineProperty(res, 'url', { value: finalUrl })
  return res
}

function entryFor(mp: typeof import('../../src/core/marketplace'), sha256?: string) {
  return mp.normalizeIndex(
    { schemaVersion: 1, entries: [{ id: 'a', kind: 'template', name: 'A', url: 'a.xml', sha256 }] },
    INDEX
  ).entries[0]
}

afterEach(() => {
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
  vi.resetModules()
})

describe('hashText', () => {
  it('is identical for LF, CRLF and BOM variants', async () => {
    const mp = await load()
    const lf = await mp.hashText(XML)
    expect(await mp.hashText(XML.replace(/\n/g, '\r\n'))).toBe(lf)
    expect(await mp.hashText('﻿' + XML)).toBe(lf)
    expect(lf).toMatch(/^[0-9a-f]{64}$/)
  })

  it('matches the build-time hash from catalog-lib', async () => {
    const mp = await load()
    const { writeFileSync, mkdtempSync, rmSync } = await import('node:fs')
    const { tmpdir } = await import('node:os')
    const { join } = await import('node:path')
    const dir = mkdtempSync(join(tmpdir(), 'wo-hash-'))
    try {
      const file = join(dir, 'a.xml')
      writeFileSync(file, '﻿' + XML.replace(/\n/g, '\r\n'), 'utf-8')
      // @ts-expect-error plain .mjs without types
      const { hashFile } = await import('../../scripts/catalog-lib.mjs')
      expect(hashFile(file)).toBe(await mp.hashText(XML))
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})

describe('normalizeIndex sha256', () => {
  it('keeps a valid hash lowercased and drops a malformed one', async () => {
    const mp = await load()
    expect(entryFor(mp, 'A'.repeat(64)).sha256).toBe('a'.repeat(64))
    expect(entryFor(mp, 'xyz').sha256).toBeUndefined()
  })
})

describe('fetchEntry', () => {
  it('returns trusted content when hash, start URL and final URL all check out', async () => {
    const mp = await load()
    vi.stubGlobal('fetch', vi.fn(async () => respond(XML, 'https://cdn.example.com/cat/a.xml')))
    const r = await mp.fetchEntry(entryFor(mp, await mp.hashText(XML)))
    expect(r.xml).toBe(XML)
    expect(r.trusted).toBe(true)
  })

  it('refuses a file that does not match the checksum', async () => {
    const mp = await load()
    vi.stubGlobal('fetch', vi.fn(async () => respond(XML + '<!-- changed -->', 'https://cdn.example.com/cat/a.xml')))
    await expect(mp.fetchEntry(entryFor(mp, await mp.hashText(XML)))).rejects.toThrow(/does not match the catalog's checksum/)
  })

  it('treats an entry without a hash as untrusted even on a trusted host', async () => {
    const mp = await load()
    vi.stubGlobal('fetch', vi.fn(async () => respond(XML, 'https://cdn.example.com/cat/a.xml')))
    expect((await mp.fetchEntry(entryFor(mp))).trusted).toBe(false)
  })

  it('treats a redirect to an untrusted host as untrusted', async () => {
    const mp = await load()
    vi.stubGlobal('fetch', vi.fn(async () => respond(XML, 'https://evil.example.net/a.xml')))
    const r = await mp.fetchEntry(entryFor(mp, await mp.hashText(XML)))
    expect(r.trusted).toBe(false)
  })

  it('treats content from an untrusted host as untrusted even with a valid hash', async () => {
    const mp = await load('')
    vi.stubGlobal('fetch', vi.fn(async () => respond(XML, 'https://cdn.example.com/cat/a.xml')))
    expect((await mp.fetchEntry(entryFor(mp, await mp.hashText(XML)))).trusted).toBe(false)
  })
})
