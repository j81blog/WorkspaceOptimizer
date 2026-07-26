/**
 * Regenerate public/marketplace/index.json from the XML files beside it.
 *
 *   npm run catalog:sync          rewrite index.json
 *   npm run catalog:sync -- --check   report what would change, exit 1 if anything would
 *
 * Deliberately NOT part of `npm run build`. The build only validates, so what deploys is
 * always exactly what is committed; changing the catalog is a reviewable commit rather
 * than a side effect of building.
 *
 * Each file's <Metadata> block is the source of truth. A file with no <Id> gets a fresh
 * GUID written into index.json, which should then be copied into the XML so the entry id
 * stays stable across regenerations.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve, join } from 'node:path'
import { discoverFiles, readXmlFile, buildEntry, pruneEntry, relPath } from './catalog-lib.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const MARKETPLACE = join(root, 'public/marketplace')
const INDEX = join(MARKETPLACE, 'index.json')
const checkOnly = process.argv.includes('--check')

if (!existsSync(INDEX)) {
  console.error(`  error  no catalog at ${relPath(root, INDEX)}`)
  process.exit(1)
}

let current
try {
  current = JSON.parse(readFileSync(INDEX, 'utf-8'))
} catch (err) {
  console.error(`  error  ${relPath(root, INDEX)} is not valid JSON: ${err.message}`)
  process.exit(1)
}

const existingByUrl = new Map((current.entries ?? []).map(e => [e.url, e]))
const files = discoverFiles(MARKETPLACE)
const entries = []
const notes = []
const errors = []

for (const file of files) {
  const xml = readXmlFile(file.absPath)
  if (!xml.ok) {
    errors.push(`${file.url} ${xml.error}`)
    continue
  }

  const existing = existingByUrl.get(file.url)
  const entry = buildEntry(file, xml, existing)

  if (!xml.id) {
    notes.push(`${file.url}: no <Id> in the XML, using ${entry.id}. Copy it into the file's <Metadata> to keep it stable.`)
  }
  if (!xml.name && !existing?.name) {
    notes.push(`${file.url}: no <Name>, falling back to the filename.`)
  }
  if (file.kind === 'snippet' && !xml.hasSupportedOs) {
    notes.push(`${file.url}: no <SupportedOS> block, so an unknown OS can only be added disabled.`)
  }
  if (existing && existing.itemCount !== xml.itemCount) {
    notes.push(`${file.url}: itemCount ${existing.itemCount ?? '(unset)'} -> ${xml.itemCount}.`)
  }

  entries.push(pruneEntry(entry))
}

// Entries pointing at files that are gone, or outside the scanned folders (like the
// bundled ../Windows.xml), are kept only when the target still exists.
const discovered = new Set(files.map(f => f.url))
for (const e of current.entries ?? []) {
  if (discovered.has(e.url)) continue
  const target = join(MARKETPLACE, e.url)
  if (existsSync(target)) {
    const xml = readXmlFile(target)
    if (xml.ok) {
      notes.push(`${e.url}: outside the template/ and snippet/ folders, kept with itemCount refreshed.`)
      entries.push(pruneEntry({ ...buildEntry({ kind: e.kind, url: e.url }, xml, e), kind: e.kind }))
      continue
    }
    errors.push(`${e.url} ${xml.error}`)
    continue
  }
  notes.push(`${e.url}: file no longer exists, entry dropped.`)
}

for (const id of dupes(entries.map(e => e.id))) {
  errors.push(`duplicate entry id "${id}", give each file a unique <Id>.`)
}

function dupes(list) {
  const seen = new Set(), dup = new Set()
  for (const v of list) (seen.has(v) ? dup : seen).add(v)
  return [...dup]
}

if (errors.length) {
  console.error(`\nCannot sync the catalog (${errors.length} error${errors.length === 1 ? '' : 's'}):\n`)
  for (const e of errors) console.error(`  error  ${e}`)
  console.error('')
  process.exit(1)
}

entries.sort((a, b) => a.kind.localeCompare(b.kind) || a.name.localeCompare(b.name))

const next = {
  schemaVersion: current.schemaVersion ?? 1,
  name: current.name ?? 'Workspace Optimizer Catalog',
  updated: new Date().toISOString().slice(0, 10),
  entries,
}

const before = readFileSync(INDEX, 'utf-8')
// Compare ignoring `updated`, so a same-day no-op run does not look like a change.
const same = JSON.stringify({ ...JSON.parse(before), updated: '' })
           === JSON.stringify({ ...next, updated: '' })
const after = JSON.stringify(next, null, 2) + '\n'

for (const n of notes) console.log(`  note   ${n}`)

/** List what the catalog now contains, so "up to date" is verifiable rather than opaque. */
function listEntries() {
  for (const e of entries) {
    console.log(`         ${e.kind.padEnd(8)} ${e.url.padEnd(30)} ${e.name} (${e.itemCount ?? '?'} items)`)
  }
}

if (same) {
  console.log(`  catalog is up to date, ${entries.length} ${entries.length === 1 ? 'entry' : 'entries'} already match the files:`)
  listEntries()
  process.exit(0)
}

if (checkOnly) {
  console.error(`\n  error  ${relPath(root, INDEX)} is out of date. Run: npm run catalog:sync\n`)
  process.exit(1)
}

writeFileSync(INDEX, after)
console.log(`  wrote ${relPath(root, INDEX)}: ${entries.length} ${entries.length === 1 ? 'entry' : 'entries'}:`)
listEntries()
