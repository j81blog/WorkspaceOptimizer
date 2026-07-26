/**
 * Marketplace catalog access.
 *
 * The catalog is a JSON index hosted anywhere CORS-reachable, configured at build
 * time via VITE_MARKETPLACE_URL (a GitHub Actions repository Variable, mirroring the
 * VITE_BRAND_* pattern in branding.ts). When the variable is unset the entire
 * Marketplace UI is hidden.
 *
 * The host must send Access-Control-Allow-Origin. raw.githubusercontent.com sends `*`
 * and is the recommended hosting pattern; GitHub Pages does not by default.
 */

export interface MarketplaceEntry {
  id: string
  kind: 'template' | 'snippet'
  name: string
  description: string
  version: string
  author: string
  category: string
  tags: string[]
  itemCount: number | null
  url: string             // as written in the index; resolve with resolveEntryUrl

  /** Index this entry came from. Set when merging, so entries stay distinguishable. */
  catalogUrl: string
  /** Display name of the source catalog, falling back to its host. */
  catalogName: string
  /** Unique across catalogs even when two share an `id`. Use as the list key. */
  uid: string
}

export interface MarketplaceIndex {
  schemaVersion: number
  name: string
  updated: string
  entries: MarketplaceEntry[]
  warnings: string[]
}

/** One catalog's load outcome, so a single failure never hides the others. */
export interface CatalogResult {
  url: string
  ok: boolean
  index: MarketplaceIndex | null
  error: string | null
}

export interface MergedCatalog {
  entries: MarketplaceEntry[]
  /** Per-catalog outcomes, in configured order. */
  results: CatalogResult[]
  warnings: string[]
  updated: string
}

export type MarketplaceErrorKind = 'network' | 'http' | 'parse' | 'too-large' | 'not-found'

export class MarketplaceError extends Error {
  constructor(message: string, public kind: MarketplaceErrorKind, public status?: number) {
    super(message)
    this.name = 'MarketplaceError'
  }
}

/** Highest index schemaVersion this build understands. */
const SUPPORTED_SCHEMA = 1
/** Refuse catalog entries larger than this. */
const MAX_ENTRY_BYTES = 2 * 1024 * 1024

function str(v: unknown): string {
  return typeof v === 'string' ? v.trim() : ''
}

/**
 * Split a comma, semicolon or newline separated variable into trimmed, non-empty parts.
 *
 * Spaces and tabs are deliberately NOT separators: a value containing one is far more
 * likely to be a typo than two entries, and splitting it would quietly turn
 * `not a host!!` into three plausible-looking hosts. Keeping it whole lets the
 * validator reject it instead. Newlines stay in, so multi-line YAML values work.
 */
export function parseList(raw: unknown): string[] {
  return str(raw).split(/[,;\r\n]+/).map(s => s.trim()).filter(Boolean)
}

/** Treat "true"/"1"/"yes"/"on" (any case) as true; everything else as false. */
export function parseFlag(raw: unknown): boolean {
  return /^(true|1|yes|on)$/i.test(str(raw))
}

/** The catalog bundled with the app, used when no others are configured. */
const bundledCatalogUrl = `${import.meta.env.BASE_URL}marketplace/index.json`

/** Whether the catalog shipped in public/ is excluded from the list. */
export const bundledCatalogDisabled = parseFlag(import.meta.env.VITE_MARKETPLACE_DISABLE_BUNDLED)

/**
 * Catalog locations, in load order.
 *
 * The bundled catalog loads first and configured URLs are *appended*, so a fork that
 * points VITE_MARKETPLACE_URL at its own index gets both. A deployment that wants
 * only its own catalogs sets VITE_MARKETPLACE_DISABLE_BUNDLED=true, which drops the
 * bundled one regardless of what the inherited file contains, so upstream catalog
 * content can never reappear through a merge.
 *
 * VITE_MARKETPLACE_URL accepts several URLs separated by a comma, semicolon or
 * newline. Duplicates are collapsed, so listing the bundled path explicitly alongside
 * others is harmless.
 */
export const marketplaceUrls: string[] = (() => {
  const configured = parseList(import.meta.env.VITE_MARKETPLACE_URL)
  const urls = bundledCatalogDisabled ? configured : [bundledCatalogUrl, ...configured]
  // Deliberately no fallback: disabling the bundled catalog with nothing configured
  // yields an empty list, and the dialog says so. Quietly re-adding the bundled
  // catalog would make the flag do the opposite of its name.
  return [...new Set(urls)]
})()

/**
 * First configured catalog, for callers that need a single reference point. Falls
 * back to the bundled path purely so relative entry URLs still resolve against
 * something sane; it does not mean that catalog is loaded.
 */
export const marketplaceUrl: string = marketplaceUrls[0] ?? bundledCatalogUrl

/** Whether the app is running on just the bundled catalog. */
export const usingBundledCatalog =
  marketplaceUrls.length === 1 && marketplaceUrls[0] === bundledCatalogUrl

/** True when configuration leaves no catalog to load at all. */
export const noCatalogsConfigured = marketplaceUrls.length === 0

/**
 * Hosts trusted to serve marketplace content without an acknowledgement prompt.
 * Same-origin content is always trusted; this extends that to named external hosts.
 * Values may be bare hosts (`cdn.example.com`) or full URLs, whose host is taken.
 */
export const trustedHosts: string[] = parseList(import.meta.env.VITE_MARKETPLACE_TRUSTED_HOSTS)
  .map(v => {
    try {
      return new URL(v.includes('//') ? v : `https://${v}`).host.toLowerCase()
    } catch {
      return v.toLowerCase()
    }
  })
  .filter(Boolean)

/** Feature switches, so a deployment can ship without either import route. */
export const marketplaceDisabled = parseFlag(import.meta.env.VITE_DISABLE_MARKETPLACE)
export const regImportDisabled = parseFlag(import.meta.env.VITE_DISABLE_REG_IMPORT)

/**
 * Whether content from `url` may be imported without the external-content
 * acknowledgement: either it is same-origin, or its host is explicitly trusted.
 */
export function isTrustedSource(url: string, pageOrigin: string): boolean {
  if (isSameOrigin(url, pageOrigin)) return true
  try {
    return trustedHosts.includes(new URL(url, pageOrigin).host.toLowerCase())
  } catch {
    return false
  }
}

/**
 * Resolve an entry URL against the index URL. Absolute URLs win; relative,
 * root-relative and `../` forms all resolve as you would expect. A malformed value
 * is returned unchanged so the caller can surface it rather than crashing.
 */
export function resolveEntryUrl(entryUrl: string, indexUrl: string): string {
  try {
    return new URL(entryUrl, indexUrl).toString()
  } catch {
    // new URL() needs an absolute base, so a relative catalog path such as
    // /marketplace/index.json lands here. Resolving against a throwaway origin keeps
    // the catalog's directory, then the origin is stripped back off. Without this the
    // entry was returned unchanged and lost its directory entirely. The bundled
    // catalog's own entries would 404.
    try {
      const base = new URL(indexUrl, 'http://_')
      const resolved = new URL(entryUrl, base)
      return resolved.origin === 'http://_'
        ? resolved.pathname + resolved.search + resolved.hash
        : resolved.toString()
    } catch {
      return entryUrl
    }
  }
}

/**
 * Whether `url` is served from `pageOrigin`.
 *
 * Resolution is relative to pageOrigin, so a path like `/marketplace/index.json` is
 * same-origin, and that is the point, since a bundled catalog must not demand an
 * external-content acknowledgement. Anything that resolves to a different origin, or
 * that cannot be resolved at all, is treated as untrusted.
 */
export function isSameOrigin(url: string, pageOrigin: string): boolean {
  try {
    return new URL(url, pageOrigin).origin === new URL(pageOrigin).origin
  } catch {
    return false
  }
}

/**
 * Short label for a catalog or entry URL: the host for absolute URLs, the path for
 * same-origin ones. Used in the trust banner and the per-catalog failure list.
 */
export function originLabel(url: string): string {
  try {
    return new URL(url).host
  } catch {
    // A relative or root-relative URL has no host; show the path, which is more
    // useful than "(unknown)" when reporting which catalog failed.
    const trimmed = str(url)
    return trimmed || '(unknown)'
  }
}

/**
 * Coerce arbitrary parsed JSON into a MarketplaceIndex. Never throws: a malformed
 * catalog degrades to fewer entries plus warnings rather than an unusable dialog.
 */
export function normalizeIndex(raw: unknown, catalogUrl = ''): MarketplaceIndex {
  const warnings: string[] = []
  const empty: MarketplaceIndex = { schemaVersion: SUPPORTED_SCHEMA, name: '', updated: '', entries: [], warnings }

  if (!raw || typeof raw !== 'object') {
    warnings.push('Catalog is not a JSON object.')
    return empty
  }
  const obj = raw as Record<string, unknown>

  const schemaVersion = typeof obj.schemaVersion === 'number' ? obj.schemaVersion : SUPPORTED_SCHEMA
  if (schemaVersion > SUPPORTED_SCHEMA) {
    warnings.push(`Catalog uses format version ${schemaVersion}; some entries may not load.`)
  }

  if (!Array.isArray(obj.entries)) {
    warnings.push('Catalog has no entries list.')
    return { ...empty, schemaVersion, name: str(obj.name), updated: str(obj.updated) }
  }

  const catalogName = str(obj.name) || (catalogUrl ? originLabel(catalogUrl) : '')
  const seen = new Set<string>()
  let skipped = 0
  const entries: MarketplaceEntry[] = []

  for (const rawEntry of obj.entries) {
    if (!rawEntry || typeof rawEntry !== 'object') { skipped++; continue }
    const e = rawEntry as Record<string, unknown>
    const id = str(e.id)
    const kind = str(e.kind)
    const name = str(e.name)
    const url = str(e.url)

    if (!id || !name || !url || (kind !== 'template' && kind !== 'snippet')) { skipped++; continue }
    // Within one catalog an id must be unique; across catalogs uid keeps them distinct.
    if (seen.has(id)) { skipped++; continue }
    seen.add(id)

    entries.push({
      id, kind, name, url,
      catalogUrl,
      catalogName,
      uid: `${catalogUrl}#${id}`,
      description: str(e.description),
      version: str(e.version),
      author: str(e.author),
      category: str(e.category),
      tags: Array.isArray(e.tags) ? e.tags.map(str).filter(Boolean) : [],
      itemCount: typeof e.itemCount === 'number' ? e.itemCount : null
    })
  }

  if (skipped > 0) warnings.push(`${skipped} catalog ${skipped === 1 ? 'entry was' : 'entries were'} skipped as unreadable.`)

  return { schemaVersion, name: str(obj.name), updated: str(obj.updated), entries, warnings }
}

/**
 * Turn a fetch failure into something a user can act on. A rejected fetch (as opposed
 * to a non-OK response) is almost always CORS or connectivity, and the browser
 * deliberately hides which, so say so rather than surfacing a bare TypeError.
 */
function networkError(url: string): MarketplaceError {
  return new MarketplaceError(
    `Could not reach ${url}. This is usually a CORS or network problem: the host must allow requests from this site.`,
    'network'
  )
}

async function fetchText(url: string, signal?: AbortSignal): Promise<string> {
  let res: Response
  try {
    res = await fetch(url, { cache: 'no-cache', redirect: 'follow', signal })
  } catch (err) {
    if ((err as Error)?.name === 'AbortError') throw err
    throw networkError(url)
  }
  if (!res.ok) {
    throw new MarketplaceError(`Request failed with HTTP ${res.status} (${url}).`, 'http', res.status)
  }
  const declared = Number(res.headers.get('content-length') ?? '')
  if (Number.isFinite(declared) && declared > MAX_ENTRY_BYTES) {
    throw new MarketplaceError('That catalog entry is too large to load.', 'too-large')
  }
  const text = await res.text()
  if (text.length > MAX_ENTRY_BYTES) {
    throw new MarketplaceError('That catalog entry is too large to load.', 'too-large')
  }
  // A single-page host answers an unknown path with 200 and its index.html, so a
  // wrong URL never surfaces as a 404. Catch it here rather than letting the XML or
  // JSON parser report a baffling syntax error about the app's own markup.
  if (/^\s*(<!doctype html|<html[\s>])/i.test(text)) {
    throw new MarketplaceError(
      `${url} returned the application page instead of a file. Check the URL, the path probably does not exist.`,
      'not-found'
    )
  }
  return text
}

/** Index cache, cleared only by a page reload or an explicit refresh. */
const indexCache = new Map<string, MarketplaceIndex>()

export function clearIndexCache() {
  indexCache.clear()
}

/** Load and normalize one catalog. */
export async function fetchIndex(
  url: string = marketplaceUrl,
  signal?: AbortSignal,
  refresh = false
): Promise<MarketplaceIndex> {
  if (!refresh) {
    const hit = indexCache.get(url)
    if (hit) return hit
  }

  const text = await fetchText(url, signal)
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    throw new MarketplaceError('The catalog is not valid JSON.', 'parse')
  }

  const index = normalizeIndex(parsed, url)
  indexCache.set(url, index)
  return index
}

/**
 * Load every configured catalog and merge them into one list.
 *
 * Catalogs are fetched concurrently and a failure is contained: the ones that loaded
 * still populate the list, and the failures are reported alongside. Entries keep a
 * `uid` scoped to their catalog, so two catalogs sharing an `id` both stay visible
 * rather than one silently shadowing the other.
 */
export async function fetchCatalogs(signal?: AbortSignal, refresh = false): Promise<MergedCatalog> {
  const results: CatalogResult[] = await Promise.all(
    marketplaceUrls.map(async (url): Promise<CatalogResult> => {
      try {
        return { url, ok: true, index: await fetchIndex(url, signal, refresh), error: null }
      } catch (err) {
        if ((err as Error)?.name === 'AbortError') throw err
        const message = err instanceof MarketplaceError ? err.message : (err as Error).message
        return { url, ok: false, index: null, error: message }
      }
    })
  )

  const warnings: string[] = []
  const entries: MarketplaceEntry[] = []
  const idCounts = new Map<string, number>()

  for (const r of results) {
    if (!r.index) continue
    warnings.push(...r.index.warnings)
    for (const e of r.index.entries) {
      entries.push(e)
      idCounts.set(e.id, (idCounts.get(e.id) ?? 0) + 1)
    }
  }

  const clashes = [...idCounts.entries()].filter(([, n]) => n > 1).map(([id]) => id)
  if (clashes.length) {
    warnings.push(
      `${clashes.length} entry ${clashes.length === 1 ? 'id appears' : 'ids appear'} in more than one catalog ` +
      `(${clashes.slice(0, 3).join(', ')}${clashes.length > 3 ? '…' : ''}). All copies are listed; check the source of each.`
    )
  }

  const updated = results
    .map(r => r.index?.updated ?? '')
    .filter(Boolean)
    .sort()
    .pop() ?? ''

  return { entries, results, warnings, updated }
}

/** Fetch one entry's XML, resolved against the catalog the entry came from. */
export async function fetchEntryXml(entry: MarketplaceEntry, signal?: AbortSignal): Promise<string> {
  return fetchText(resolveEntryUrl(entry.url, entry.catalogUrl || marketplaceUrl), signal)
}
