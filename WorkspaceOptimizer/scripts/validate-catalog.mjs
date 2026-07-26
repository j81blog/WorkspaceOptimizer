/**
 * Build-time validation for the marketplace configuration.
 *
 * Catalogs are fetched in the browser at runtime, so this cannot inspect remote ones.
 * It validates everything that IS knowable at build time and fails the build on error:
 *
 *   - the bundled public/marketplace/index.json parses, has a supported schemaVersion,
 *     and contains no duplicate entry ids or malformed entries
 *   - VITE_MARKETPLACE_URL entries are syntactically valid and not duplicated
 *   - VITE_MARKETPLACE_TRUSTED_HOSTS entries look like hosts
 *   - the disable flags use a recognized boolean spelling
 *
 * Run automatically via the `prebuild` npm script.
 */
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve, join } from 'node:path'
import { discoverFiles, readXmlFile } from './catalog-lib.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const MARKETPLACE = resolve(root, 'public/marketplace')
const CATALOG = join(MARKETPLACE, 'index.json')
const SUPPORTED_SCHEMA = 1
const TRUTHY = /^(true|1|yes|on)$/i
const FALSY = /^(false|0|no|off)$/i

const errors = []
const warnings = []

// Mirrors parseList in src/core/marketplace.ts: comma, semicolon and newline only.
// Spaces are not separators, so a typo stays one entry and gets rejected below.
const list = (raw) => String(raw ?? '').split(/[,;\r\n]+/).map(s => s.trim()).filter(Boolean)

// ── bundled catalog ──────────────────────────────────────────────────────────
if (!existsSync(CATALOG)) {
  errors.push(`Bundled catalog missing: ${CATALOG}`)
} else {
  let parsed
  try {
    parsed = JSON.parse(readFileSync(CATALOG, 'utf-8'))
  } catch (err) {
    errors.push(`Bundled catalog is not valid JSON: ${err.message}`)
  }

  if (parsed !== undefined) {
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      errors.push('Bundled catalog must be a JSON object.')
    } else {
      if (typeof parsed.schemaVersion !== 'number') {
        errors.push('Bundled catalog is missing a numeric "schemaVersion".')
      } else if (parsed.schemaVersion > SUPPORTED_SCHEMA) {
        errors.push(`Bundled catalog uses schemaVersion ${parsed.schemaVersion}; this build supports ${SUPPORTED_SCHEMA}.`)
      }

      if (!Array.isArray(parsed.entries)) {
        errors.push('Bundled catalog is missing an "entries" array.')
      } else {
        const seen = new Map()
        parsed.entries.forEach((e, i) => {
          const at = `entries[${i}]`
          if (!e || typeof e !== 'object') { errors.push(`${at} is not an object.`); return }
          for (const field of ['id', 'kind', 'name', 'url']) {
            if (!e[field] || typeof e[field] !== 'string' || !e[field].trim()) {
              errors.push(`${at} is missing a non-empty "${field}".`)
            }
          }
          if (e.kind && e.kind !== 'template' && e.kind !== 'snippet') {
            errors.push(`${at} has kind "${e.kind}"; expected "template" or "snippet".`)
          }
          if (typeof e.id === 'string' && e.id.trim()) {
            const prev = seen.get(e.id)
            if (prev !== undefined) errors.push(`Duplicate entry id "${e.id}" (entries[${prev}] and ${at}).`)
            else seen.set(e.id, i)
          }
        })
      }
    }
  }
}

// ── catalog entries vs. the files on disk ────────────────────────────────────
// The most valuable check here: a broken XML would otherwise only fail in a user's
// browser at import time, with no build-time signal at all.
if (existsSync(CATALOG)) {
  let cat
  try { cat = JSON.parse(readFileSync(CATALOG, 'utf-8')) } catch { cat = null }
  const entries = Array.isArray(cat?.entries) ? cat.entries : []

  const referenced = new Set()
  for (const e of entries) {
    const url = typeof e?.url === 'string' ? e.url.trim() : ''
    if (!url) continue
    // Only same-origin, relative URLs point at files in this repo.
    if (/^(https?:)?\/\//i.test(url)) continue
    referenced.add(url)

    const target = join(MARKETPLACE, url)
    if (!existsSync(target)) {
      errors.push(`Entry "${e.id ?? url}" points at ${url}, which does not exist.`)
      continue
    }
    const xml = readXmlFile(target)
    if (!xml.ok) {
      errors.push(`Entry "${e.id ?? url}" points at ${url}, which ${xml.error}.`)
      continue
    }
    if (typeof e.itemCount === 'number' && e.itemCount !== xml.itemCount) {
      warnings.push(`Entry "${e.id ?? url}" claims ${e.itemCount} items; ${url} has ${xml.itemCount}. Run: npm run catalog:sync`)
    }
    if (e.kind === 'snippet' && !xml.hasSupportedOs) {
      warnings.push(`${url} has no <SupportedOS> block, so an OS it references can only be added disabled.`)
    }
  }

  // An XML sitting in template/ or snippet/ that nothing references would never appear
  // in the Marketplace, almost always a forgotten catalog entry.
  for (const f of discoverFiles(MARKETPLACE)) {
    if (!referenced.has(f.url)) {
      warnings.push(`${f.url} is not referenced by any catalog entry. Run: npm run catalog:sync`)
    }
  }
}

// ── VITE_MARKETPLACE_URL ─────────────────────────────────────────────────────
const urls = list(process.env.VITE_MARKETPLACE_URL)
const seenUrls = new Set()
for (const u of urls) {
  if (seenUrls.has(u)) { warnings.push(`VITE_MARKETPLACE_URL lists "${u}" more than once.`); continue }
  seenUrls.add(u)

  // new URL() percent-encodes an embedded space rather than rejecting it, so
  // "https://a/x.json https://b/y.json" would silently become one broken URL.
  // Spaces are not separators, so this can only be a typo.
  if (/\s/.test(u)) {
    errors.push(`VITE_MARKETPLACE_URL entry "${u}" contains a space. Separate catalogs with a comma, semicolon or newline.`)
    continue
  }

  const looksRelative = u.startsWith('/') || u.startsWith('./') || u.startsWith('../')
  if (looksRelative) continue
  try {
    const parsed = new URL(u)
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      errors.push(`VITE_MARKETPLACE_URL entry "${u}" must use http(s).`)
    }
  } catch {
    errors.push(`VITE_MARKETPLACE_URL entry "${u}" is not a valid URL or path.`)
  }
}

// ── VITE_MARKETPLACE_TRUSTED_HOSTS ───────────────────────────────────────────
// A typo here silently becomes a trust grant, so validate the shape strictly rather
// than relying on URL(), which happily accepts "!!!" as a hostname.
const HOSTNAME = /^(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/i
for (const h of list(process.env.VITE_MARKETPLACE_TRUSTED_HOSTS)) {
  if (/\s/.test(h)) {
    errors.push(`VITE_MARKETPLACE_TRUSTED_HOSTS entry "${h}" contains a space. Separate hosts with a comma, semicolon or newline.`)
    continue
  }
  let host = h
  try {
    host = new URL(h.includes('//') ? h : `https://${h}`).host
  } catch {
    errors.push(`VITE_MARKETPLACE_TRUSTED_HOSTS entry "${h}" is not a valid host.`)
    continue
  }
  // Strip an optional :port before checking the name itself.
  const name = host.replace(/:\d+$/, '')
  if (!name || !HOSTNAME.test(name)) {
    errors.push(`VITE_MARKETPLACE_TRUSTED_HOSTS entry "${h}" is not a valid host name.`)
  } else if (!name.includes('.') && name !== 'localhost') {
    warnings.push(`VITE_MARKETPLACE_TRUSTED_HOSTS entry "${h}" has no dot. Is it a typo?`)
  }
}

// ── boolean flags ────────────────────────────────────────────────────────────
for (const name of ['VITE_DISABLE_MARKETPLACE', 'VITE_DISABLE_REG_IMPORT', 'VITE_MARKETPLACE_DISABLE_BUNDLED']) {
  const raw = String(process.env[name] ?? '').trim()
  if (raw && !TRUTHY.test(raw) && !FALSY.test(raw)) {
    errors.push(`${name}="${raw}" is not a recognized boolean. Use true/false.`)
  }
}

// ── combination checks ───────────────────────────────────────────────────────
// Dropping the bundled catalog without configuring another leaves the Marketplace
// with nothing to load. That is always a mistake: either name a catalog, or turn the
// feature off. Caught here so it never reaches a deployment.
const bundledOff = TRUTHY.test(String(process.env.VITE_MARKETPLACE_DISABLE_BUNDLED ?? '').trim())
const marketplaceOff = TRUTHY.test(String(process.env.VITE_DISABLE_MARKETPLACE ?? '').trim())
if (bundledOff && urls.length === 0 && !marketplaceOff) {
  errors.push(
    'VITE_MARKETPLACE_DISABLE_BUNDLED is set but VITE_MARKETPLACE_URL is empty, ' +
    'leaving no catalog to load. Set a catalog URL, or turn the Marketplace off ' +
    'with VITE_DISABLE_MARKETPLACE=true.'
  )
}

// ── report ───────────────────────────────────────────────────────────────────
for (const w of warnings) console.warn(`  warning  ${w}`)

if (errors.length) {
  console.error(`\nMarketplace configuration is invalid (${errors.length} error${errors.length === 1 ? '' : 's'}):\n`)
  for (const e of errors) console.error(`  error  ${e}`)
  console.error('')
  process.exit(1)
}

const count = urls.length || 1
console.log(`  marketplace config OK (${count} catalog${count === 1 ? '' : 's'})`)
