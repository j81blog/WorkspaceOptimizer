import { describe, it, expect, afterEach, vi } from 'vitest'
import { resolveEntryUrl, isSameOrigin, originLabel, normalizeIndex } from '../../src/core/marketplace'

const INDEX = 'https://raw.githubusercontent.com/acme/cat/main/index.json'

/**
 * marketplaceUrl is read from import.meta.env once at module load, so the fetch
 * tests need a fresh import per scenario. Mirrors the helper in branding-vars.test.ts.
 */
async function loadMarketplace(url: string | undefined) {
  vi.resetModules()
  vi.stubEnv('VITE_MARKETPLACE_URL', url ?? '')
  return await import('../../src/core/marketplace')
}

afterEach(() => {
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
  vi.resetModules()
})

describe('resolveEntryUrl', () => {
  it.each([
    ['snippets/a.xml', 'https://raw.githubusercontent.com/acme/cat/main/snippets/a.xml'],
    ['./a.xml', 'https://raw.githubusercontent.com/acme/cat/main/a.xml'],
    ['../shared/a.xml', 'https://raw.githubusercontent.com/acme/cat/shared/a.xml'],
    ['/abs/a.xml', 'https://raw.githubusercontent.com/abs/a.xml'],
    ['https://cdn.example.com/a.xml', 'https://cdn.example.com/a.xml'],
  ])('resolves %s', (entry, expected) => {
    expect(resolveEntryUrl(entry, INDEX)).toBe(expected)
  })

  it('falls back to a root-relative path when the index URL is unusable', () => {
    // An unusable base has no directory to inherit, so the entry resolves from the
    // site root, still fetchable, unlike a bare filename.
    expect(resolveEntryUrl('a.xml', 'not a url')).toBe('/a.xml')
    expect(resolveEntryUrl('a.xml', '')).toBe('/a.xml')
  })

  // Regression: new URL() needs an absolute base, so a relative catalog path used to
  // fall into the catch and return the entry unchanged, dropping the directory and
  // 404ing every entry in the bundled catalog.
  it.each([
    ['sibling file',   'a.xml',                 '/marketplace/index.json', '/marketplace/a.xml'],
    ['subdirectory',   'snippets/a.xml',        '/marketplace/index.json', '/marketplace/snippets/a.xml'],
    ['parent',         '../shared/a.xml',       '/marketplace/index.json', '/shared/a.xml'],
    ['root-relative',  '/other/a.xml',          '/marketplace/index.json', '/other/a.xml'],
    ['absolute entry', 'https://cdn.io/a.xml',  '/marketplace/index.json', 'https://cdn.io/a.xml'],
    ['subpath deploy', 'a.xml',                 '/wo/marketplace/index.json', '/wo/marketplace/a.xml'],
  ])('resolves a %s against a relative catalog path', (_label, entry, index, expected) => {
    expect(resolveEntryUrl(entry, index)).toBe(expected)
  })
})

describe('isSameOrigin', () => {
  it('is true for the same scheme, host and port', () => {
    expect(isSameOrigin('https://app.example.com/x.xml', 'https://app.example.com')).toBe(true)
  })

  it('is false across hosts', () => {
    expect(isSameOrigin('https://cdn.example.com/x.xml', 'https://app.example.com')).toBe(false)
  })

  it('is false across schemes on the same host', () => {
    expect(isSameOrigin('http://app.example.com/x.xml', 'https://app.example.com')).toBe(false)
  })

  it('is false across ports', () => {
    expect(isSameOrigin('https://app.example.com:8443/x', 'https://app.example.com')).toBe(false)
  })

  it('treats a relative URL as same-origin, so a bundled catalog needs no warning', () => {
    expect(isSameOrigin('/marketplace/index.json', 'https://app.example.com')).toBe(true)
  })

  it('is false when the page origin itself is unusable', () => {
    expect(isSameOrigin('/a.xml', 'not an origin')).toBe(false)
  })

  it('does not let a protocol-relative URL masquerade as same-origin', () => {
    expect(isSameOrigin('//evil.example.com/a.xml', 'https://app.example.com')).toBe(false)
  })
})

describe('originLabel', () => {
  it('returns the host', () => {
    expect(originLabel('https://raw.githubusercontent.com/a/b')).toBe('raw.githubusercontent.com')
  })

  it('shows the path for a same-origin catalog, which has no host', () => {
    expect(originLabel('/marketplace/index.json')).toBe('/marketplace/index.json')
  })

  it('falls back only when there is nothing to show', () => {
    expect(originLabel('')).toBe('(unknown)')
    expect(originLabel('   ')).toBe('(unknown)')
  })
})

describe('normalizeIndex', () => {
  const valid = {
    schemaVersion: 1,
    name: 'Catalog',
    updated: '2026-07-20',
    entries: [
      { id: 'a', kind: 'snippet', name: 'A', url: 'a.xml', description: 'd', version: '1.0', author: 'me', category: 'C', tags: ['x'], itemCount: 3 },
      { id: 'b', kind: 'template', name: 'B', url: 'b.xml' },
    ]
  }

  it('reads a valid index', () => {
    const idx = normalizeIndex(valid)
    expect(idx.entries).toHaveLength(2)
    expect(idx.name).toBe('Catalog')
    expect(idx.entries[0]).toMatchObject({ id: 'a', kind: 'snippet', tags: ['x'], itemCount: 3 })
    expect(idx.warnings).toHaveLength(0)
  })

  it('defaults optional fields', () => {
    expect(normalizeIndex(valid).entries[1]).toMatchObject({ description: '', tags: [], itemCount: null })
  })

  it.each([
    ['missing id', { kind: 'snippet', name: 'X', url: 'x.xml' }],
    ['missing name', { id: 'x', kind: 'snippet', url: 'x.xml' }],
    ['missing url', { id: 'x', kind: 'snippet', name: 'X' }],
    ['unknown kind', { id: 'x', kind: 'script', name: 'X', url: 'x.xml' }],
  ])('drops an entry with %s', (_label, entry) => {
    const idx = normalizeIndex({ schemaVersion: 1, entries: [entry] })
    expect(idx.entries).toHaveLength(0)
    expect(idx.warnings.some(w => w.includes('skipped'))).toBe(true)
  })

  it('keeps the first of a duplicate id', () => {
    const idx = normalizeIndex({ schemaVersion: 1, entries: [
      { id: 'dup', kind: 'snippet', name: 'First', url: 'a.xml' },
      { id: 'dup', kind: 'snippet', name: 'Second', url: 'b.xml' },
    ]})
    expect(idx.entries).toHaveLength(1)
    expect(idx.entries[0].name).toBe('First')
  })

  it('warns about a newer schema but still returns entries', () => {
    const idx = normalizeIndex({ ...valid, schemaVersion: 2 })
    expect(idx.entries).toHaveLength(2)
    expect(idx.warnings.some(w => w.includes('format version 2'))).toBe(true)
  })

  it.each([
    ['a non-array entries field', { schemaVersion: 1, entries: 'nope' }],
    ['null', null],
    ['undefined', undefined],
    ['a bare string', 'nope'],
  ])('returns an empty index for %s', (_label, input) => {
    const idx = normalizeIndex(input)
    expect(idx.entries).toHaveLength(0)
    expect(idx.warnings.length).toBeGreaterThan(0)
  })
})

describe('fetchIndex', () => {
  const ok = (body: string) => new Response(body, { status: 200 })

  it('falls back to the bundled catalog when no URL is configured', async () => {
    const mp = await loadMarketplace(undefined)
    expect(mp.marketplaceUrl).toBe('/marketplace/index.json')
    expect(mp.usingBundledCatalog).toBe(true)

    const spy = vi.fn(async (_url: string) => ok(JSON.stringify({ schemaVersion: 1, entries: [] })))
    vi.stubGlobal('fetch', spy)
    await mp.fetchIndex()
    expect(spy.mock.calls[0][0]).toBe('/marketplace/index.json')
  })

  it('adds a configured URL alongside the bundled catalog', async () => {
    const mp = await loadMarketplace(INDEX)
    expect(mp.marketplaceUrls).toContain(INDEX)
    expect(mp.marketplaceUrls).toContain('/marketplace/index.json')
    expect(mp.usingBundledCatalog).toBe(false)
  })

  it('maps a 404 to an http error carrying the status', async () => {
    const mp = await loadMarketplace(INDEX)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('', { status: 404 })))
    await expect(mp.fetchIndex()).rejects.toMatchObject({ kind: 'http', status: 404 })
  })

  it('maps a rejected fetch to a network error that mentions CORS', async () => {
    const mp = await loadMarketplace(INDEX)
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')))
    await expect(mp.fetchIndex()).rejects.toMatchObject({ kind: 'network', message: expect.stringMatching(/CORS/) })
  })

  it.each([
    ['<!doctype html>\n<html><body>app</body></html>'],
    ['<!DOCTYPE HTML><html></html>'],
    ['  <html lang="en"><head></head></html>'],
  ])('detects an SPA fallback page rather than reporting a syntax error', async (body) => {
    // A single-page host answers an unknown path with 200 + index.html, so the
    // wrong-URL case has to be caught by content, not status.
    const mp = await loadMarketplace(INDEX)
    vi.stubGlobal('fetch', vi.fn(async () => ok(body)))
    await expect(mp.fetchIndex()).rejects.toMatchObject({ kind: 'not-found' })
    await expect(mp.fetchIndex()).rejects.toThrow(/path probably does not exist/)
  })

  it('does not mistake XML or JSON for an HTML page', async () => {
    const mp = await loadMarketplace(INDEX)
    vi.stubGlobal('fetch', vi.fn(async () => ok(JSON.stringify({ schemaVersion: 1, entries: [] }))))
    await expect(mp.fetchIndex()).resolves.toMatchObject({ entries: [] })
  })

  it('maps invalid JSON to a parse error', async () => {
    const mp = await loadMarketplace(INDEX)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(ok('{ not json')))
    await expect(mp.fetchIndex()).rejects.toMatchObject({ kind: 'parse' })
  })

  it('caches the index and refetches only when asked', async () => {
    const mp = await loadMarketplace(INDEX)
    // A Response body can only be read once, so hand out a fresh one per call.
    const spy = vi.fn(async () => ok(JSON.stringify({ schemaVersion: 1, entries: [] })))
    vi.stubGlobal('fetch', spy)

    await mp.fetchIndex()
    await mp.fetchIndex()
    expect(spy).toHaveBeenCalledTimes(1)

    await mp.fetchIndex(undefined, undefined, true)
    expect(spy).toHaveBeenCalledTimes(2)
  })
})

describe('parseList / parseFlag', () => {
  it.each([
    ['a,b,c', ['a', 'b', 'c']],
    ['a, b ,c', ['a', 'b', 'c']],
    ['a;b', ['a', 'b']],
    ['a\nb\n c ', ['a', 'b', 'c']],          // newlines split; surrounding spaces trim
    ['a,,b', ['a', 'b']],                     // empty parts dropped
    ['a,\n;b', ['a', 'b']],                   // mixed separators collapse
    ['', []],
    ['   ', []],
  ])('splits %j', async (raw, expected) => {
    const { parseList } = await import('../../src/core/marketplace')
    expect(parseList(raw)).toEqual(expected)
  })

  it('does not split on spaces, so a typo stays one rejectable entry', async () => {
    const { parseList } = await import('../../src/core/marketplace')
    expect(parseList('not a host!!')).toEqual(['not a host!!'])
    expect(parseList('a.example.com b.example.com')).toEqual(['a.example.com b.example.com'])
  })

  it.each([['true', true], ['TRUE', true], ['1', true], ['yes', true], ['on', true],
           ['false', false], ['0', false], ['', false], ['maybe', false]])(
    'reads %j as %s', async (raw, expected) => {
      const { parseFlag } = await import('../../src/core/marketplace')
      expect(parseFlag(raw)).toBe(expected)
    })
})

describe('bundled catalog', () => {
  const OWN = 'https://own.example.com/cat/index.json'
  const BUNDLED = '/marketplace/index.json'

  async function loadWith(url: string, disableBundled = '') {
    vi.resetModules()
    vi.stubEnv('VITE_MARKETPLACE_URL', url)
    vi.stubEnv('VITE_MARKETPLACE_DISABLE_BUNDLED', disableBundled)
    return await import('../../src/core/marketplace')
  }

  it('uses only the bundled catalog when nothing is configured', async () => {
    const mp = await loadWith('')
    expect(mp.marketplaceUrls).toEqual([BUNDLED])
    expect(mp.usingBundledCatalog).toBe(true)
  })

  it('appends configured catalogs to the bundled one by default', async () => {
    const mp = await loadWith(OWN)
    expect(mp.marketplaceUrls).toEqual([BUNDLED, OWN])
    expect(mp.usingBundledCatalog).toBe(false)
  })

  it('drops the bundled catalog when explicitly disabled', async () => {
    const mp = await loadWith(OWN, 'true')
    expect(mp.marketplaceUrls).toEqual([OWN])
    expect(mp.bundledCatalogDisabled).toBe(true)
  })

  it('loads nothing when the bundled catalog is disabled and none is configured', async () => {
    // The flag has to mean what it says. Silently re-adding the bundled catalog here
    // would make it do the opposite; the dialog explains the situation instead.
    const mp = await loadWith('', 'true')
    expect(mp.marketplaceUrls).toEqual([])
    expect(mp.noCatalogsConfigured).toBe(true)
    expect(mp.usingBundledCatalog).toBe(false)
  })

  it('reports catalogs as configured in every other case', async () => {
    expect((await loadWith('')).noCatalogsConfigured).toBe(false)
    expect((await loadWith(OWN)).noCatalogsConfigured).toBe(false)
    expect((await loadWith(OWN, 'true')).noCatalogsConfigured).toBe(false)
  })

  it('does not list the bundled catalog twice when named explicitly', async () => {
    const mp = await loadWith(`${BUNDLED},${OWN}`)
    expect(mp.marketplaceUrls).toEqual([BUNDLED, OWN])
  })
})

describe('multiple catalogs', () => {
  const A = 'https://a.example.com/cat/index.json'
  const B = 'https://b.example.com/cat/index.json'

  async function loadWith(urls: string) {
    vi.resetModules()
    vi.stubEnv('VITE_MARKETPLACE_URL', urls)
    // These tests are about merging the configured catalogs, so keep the bundled
    // one out of the way.
    vi.stubEnv('VITE_MARKETPLACE_DISABLE_BUNDLED', 'true')
    return await import('../../src/core/marketplace')
  }

  it('parses several URLs from one variable', async () => {
    const mp = await loadWith(`${A}, ${B}`)
    expect(mp.marketplaceUrls).toEqual([A, B])
    expect(mp.usingBundledCatalog).toBe(false)
  })

  it('merges entries and stamps each with its source catalog', async () => {
    const mp = await loadWith(`${A},${B}`)
    vi.stubGlobal('fetch', vi.fn(async (url: string) => new Response(JSON.stringify({
      schemaVersion: 1,
      name: url === A ? 'Cat A' : 'Cat B',
      entries: [{ id: url === A ? 'one' : 'two', kind: 'snippet', name: 'X', url: 'x.xml' }]
    }), { status: 200 })))

    const merged = await mp.fetchCatalogs()
    expect(merged.entries).toHaveLength(2)
    expect(merged.entries.map(e => e.catalogName).sort()).toEqual(['Cat A', 'Cat B'])
    expect(merged.results.every(r => r.ok)).toBe(true)
  })

  it('keeps both copies when two catalogs share an entry id, and warns', async () => {
    const mp = await loadWith(`${A},${B}`)
    vi.stubGlobal('fetch', vi.fn(async (url: string) => new Response(JSON.stringify({
      schemaVersion: 1,
      name: url === A ? 'Cat A' : 'Cat B',
      entries: [{ id: 'same', kind: 'snippet', name: url === A ? 'From A' : 'From B', url: 'x.xml' }]
    }), { status: 200 })))

    const merged = await mp.fetchCatalogs()
    expect(merged.entries).toHaveLength(2)
    expect(new Set(merged.entries.map(e => e.uid)).size).toBe(2)   // uids stay distinct
    expect(merged.warnings.some(w => w.includes('more than one catalog'))).toBe(true)
  })

  it('skips a failing catalog and still returns the others', async () => {
    const mp = await loadWith(`${A},${B}`)
    vi.stubGlobal('fetch', vi.fn(async (url: string) =>
      url === A
        ? new Response(JSON.stringify({ schemaVersion: 1, entries: [{ id: 'ok', kind: 'snippet', name: 'OK', url: 'x.xml' }] }), { status: 200 })
        : new Response('', { status: 500 })))

    const merged = await mp.fetchCatalogs()
    expect(merged.entries).toHaveLength(1)
    expect(merged.results.filter(r => !r.ok)).toHaveLength(1)
    expect(merged.results.find(r => !r.ok)!.error).toContain('500')
  })
})

describe('trusted hosts', () => {
  async function loadTrusting(hosts: string) {
    vi.resetModules()
    vi.stubEnv('VITE_MARKETPLACE_TRUSTED_HOSTS', hosts)
    return await import('../../src/core/marketplace')
  }

  it('treats a whitelisted host as trusted without an acknowledgement', async () => {
    const mp = await loadTrusting('raw.githubusercontent.com, cdn.contoso.example')
    expect(mp.isTrustedSource('https://raw.githubusercontent.com/a/b.xml', 'https://app.example.com')).toBe(true)
    expect(mp.isTrustedSource('https://cdn.contoso.example/b.xml', 'https://app.example.com')).toBe(true)
  })

  it('still requires acknowledgement for hosts not listed', async () => {
    const mp = await loadTrusting('raw.githubusercontent.com')
    expect(mp.isTrustedSource('https://evil.example.com/b.xml', 'https://app.example.com')).toBe(false)
  })

  it('accepts a full URL in the whitelist and uses its host', async () => {
    const mp = await loadTrusting('https://cdn.example.com/some/path')
    expect(mp.trustedHosts).toEqual(['cdn.example.com'])
    expect(mp.isTrustedSource('https://cdn.example.com/other.xml', 'https://app.example.com')).toBe(true)
  })

  it('always trusts same-origin content regardless of the whitelist', async () => {
    const mp = await loadTrusting('')
    expect(mp.isTrustedSource('/marketplace/index.json', 'https://app.example.com')).toBe(true)
  })
})

describe('feature flags', () => {
  it('reads the disable flags', async () => {
    vi.resetModules()
    vi.stubEnv('VITE_DISABLE_MARKETPLACE', 'true')
    vi.stubEnv('VITE_DISABLE_REG_IMPORT', 'false')
    const mp = await import('../../src/core/marketplace')
    expect(mp.marketplaceDisabled).toBe(true)
    expect(mp.regImportDisabled).toBe(false)
  })

  it('defaults both to enabled', async () => {
    vi.resetModules()
    vi.stubEnv('VITE_DISABLE_MARKETPLACE', '')
    vi.stubEnv('VITE_DISABLE_REG_IMPORT', '')
    const mp = await import('../../src/core/marketplace')
    expect(mp.marketplaceDisabled).toBe(false)
    expect(mp.regImportDisabled).toBe(false)
  })
})

describe('fetchEntryXml', () => {
  it('resolves the entry URL against the catalog it came from', async () => {
    const mp = await loadMarketplace(INDEX)
    const spy = vi.fn().mockResolvedValue(new Response('<Items></Items>', { status: 200 }))
    vi.stubGlobal('fetch', spy)

    // Deliberately a different catalog from the first configured one, to prove the
    // entry's own catalogUrl is what gets used.
    const entry = {
      id: 'a', kind: 'snippet' as const, name: 'A', url: 'snippets/a.xml',
      description: '', version: '', author: '', category: '', tags: [], itemCount: null,
      catalogUrl: 'https://other.example.com/cat/index.json',
      catalogName: 'Other', uid: 'https://other.example.com/cat/index.json#a'
    }
    await mp.fetchEntryXml(entry)

    expect(spy.mock.calls[0][0]).toBe('https://other.example.com/cat/snippets/a.xml')
  })
})
