/**
 * Shared logic for reading marketplace XML files and building catalog entries.
 *
 * Used by both `validate-catalog.mjs` (read-only, runs on every build) and
 * `sync-catalog.mjs` (rewrites index.json on demand).
 *
 * Deliberately regex-based rather than a real XML parser: this runs in plain Node with
 * no dependencies, and it only needs a handful of top-level <Metadata> fields plus an
 * item count. Anything malformed enough to defeat these patterns is reported as an
 * error rather than guessed at.
 */
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs'
import { join, relative, posix } from 'node:path'
import { randomUUID } from 'node:crypto'

/** Folders under public/marketplace/ scanned for publishable files, and their kind. */
export const KIND_DIRS = { template: 'template', snippet: 'snippet' }

function tag(xml, name) {
  // Non-greedy, and anchored to the Metadata block so an <Item> field cannot match.
  const meta = xml.match(/<Metadata>([\s\S]*?)<\/Metadata>/)
  if (!meta) return ''
  const m = meta[1].match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`))
  return m ? m[1].trim() : ''
}

function tags(xml) {
  const meta = xml.match(/<Metadata>([\s\S]*?)<\/Metadata>/)
  if (!meta) return []
  const block = meta[1].match(/<Tags>([\s\S]*?)<\/Tags>/)
  if (!block) return []
  return [...block[1].matchAll(/<Tag>([\s\S]*?)<\/Tag>/g)].map(m => m[1].trim()).filter(Boolean)
}

/**
 * Read one marketplace XML file and describe it.
 * Returns { ok: false, error } when the file cannot be used.
 */
export function readXmlFile(absPath) {
  let xml
  try {
    xml = readFileSync(absPath, 'utf-8')
  } catch (err) {
    return { ok: false, error: `cannot be read (${err.message})` }
  }

  if (!/<Items[\s>]/.test(xml)) {
    return { ok: false, error: 'is not a Workspace Optimizer template (no <Items> root)' }
  }

  const itemCount = (xml.match(/<Item>/g) ?? []).length
  if (itemCount === 0) {
    return { ok: false, error: 'contains no <Item> elements' }
  }

  return {
    ok: true,
    itemCount,
    version: tag(xml, 'Version'),
    schemaVersion: tag(xml, 'SchemaVersion'),
    id: tag(xml, 'Id'),
    name: tag(xml, 'Name'),
    description: tag(xml, 'Description'),
    author: tag(xml, 'Author'),
    category: tag(xml, 'Category'),
    tags: tags(xml),
    hasSupportedOs: /<SupportedOS>/.test(xml),
  }
}

/** Every .xml under the kind folders, as { kind, url, absPath }. */
export function discoverFiles(marketplaceDir) {
  const found = []
  for (const [kind, dir] of Object.entries(KIND_DIRS)) {
    const abs = join(marketplaceDir, dir)
    if (!existsSync(abs) || !statSync(abs).isDirectory()) continue
    for (const name of readdirSync(abs).sort()) {
      if (!name.toLowerCase().endsWith('.xml')) continue
      found.push({
        kind,
        url: posix.join(dir, name),
        absPath: join(abs, name),
      })
    }
  }
  return found
}

/**
 * Build a catalog entry for a discovered file, reusing an existing entry's editorial
 * fields where the XML does not supply them. The XML always wins when it has a value:
 * the file is the source of truth, index.json is generated from it.
 */
export function buildEntry(file, xml, existing) {
  const pick = (fromXml, fromIndex, fallback) => fromXml || fromIndex || fallback
  const base = file.url.replace(/^.*\//, '').replace(/\.xml$/i, '')

  return {
    id: pick(xml.id, existing?.id, randomUUID()),
    kind: file.kind,
    name: pick(xml.name, existing?.name, base),
    url: file.url,
    description: pick(xml.description, existing?.description, ''),
    version: pick(xml.version, existing?.version, ''),
    author: pick(xml.author, existing?.author, ''),
    category: pick(xml.category, existing?.category, ''),
    tags: xml.tags.length ? xml.tags : (existing?.tags ?? []),
    itemCount: xml.itemCount,
  }
}

/** Drop empty optional fields so generated entries stay readable. */
export function pruneEntry(e) {
  const out = { id: e.id, kind: e.kind, name: e.name, url: e.url }
  if (e.description) out.description = e.description
  if (e.version) out.version = e.version
  if (e.author) out.author = e.author
  if (e.category) out.category = e.category
  if (e.tags?.length) out.tags = e.tags
  if (typeof e.itemCount === 'number') out.itemCount = e.itemCount
  return out
}

export function relPath(root, abs) {
  return relative(root, abs).split('\\').join('/')
}
