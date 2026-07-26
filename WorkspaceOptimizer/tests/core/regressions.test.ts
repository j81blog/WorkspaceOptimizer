import { describe, it, expect } from 'vitest'
// ?raw rather than fs: the project deliberately types against vite/client only, so
// there is no @types/node to import from.
import windowsXml from '../../public/Windows.xml?raw'
import { parseXml } from '../../src/core/parser'
import { serializeXml } from '../../src/core/serializer'
import { validate } from '../../src/core/validator'
import { buildMergePlan, applyMergePlan } from '../../src/core/merge'
import { parseReg, parseRegBuffer, regEntriesToItems } from '../../src/core/regParser'
import { formatVersion } from '../../src/core/version'
import type { TemplateDocument, TemplateItem, OsDefinition } from '../../src/core/types'

/**
 * Named regression cover for defects found in review. Each test states the bug it
 * guards, so a failure here points straight at what came back rather than at an
 * abstract assertion.
 */

const W11: OsDefinition = { tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }
const OS_ON = { execute: true, physical: true, virtual: true }

function svc(name: string, service: string, os: Record<string, typeof OS_ON> = { Windows11: OS_ON }): TemplateItem {
  return {
    id: crypto.randomUUID(), name, description: '', type: 'Service', typeRaw: 'Service',
    category: 'General', order: 100, os,
    payload: { type: 'Service', name: service, action: 'Disabled' }
  }
}

const doc = (items: TemplateItem[] = [], supportedOs = [W11]): TemplateDocument =>
  ({ metadata: { version: '1', schemaVersion: '1', id: 'x', name: 'N', description: 'D', author: 'A', category: '', tags: [] }, supportedOs, items })

describe('regression: an item that can run nowhere is flagged', () => {
  // Only an item with no OS tags at all is truly dead; every missing tag can now be
  // added from the preview, so a droppable tag is not the same as a dead item.
  it('notes an item with no OS mappings whatsoever', () => {
    const plan = buildMergePlan(doc(), [svc('Orphan', 'x', {})])
    expect(plan.rows[0].notes).toContain('will not run on any OS')
  })

  it('stays quiet when the tag can be accepted, carried or stubbed', () => {
    const s2019: OsDefinition = { tag: 'Server2019', name: 'Server 2019', abbreviation: 'WS2019', isServerOs: true, buildStartsWith: ['17'] }
    expect(buildMergePlan(doc(), [svc('Fine', 'x', { Server2019: OS_ON })], [s2019]).rows[0].notes)
      .not.toContain('will not run on any OS')
    expect(buildMergePlan(doc(), [svc('Stub', 'x', { Server2012: OS_ON })]).rows[0].notes)
      .not.toContain('will not run on any OS')
  })

  it('never leaves an accepted stub OS enabled, since it matches no machine', () => {
    const plan = buildMergePlan(doc(), [svc('Stub', 'x', { Server2012: OS_ON })])
    plan.missingOs[0].accepted = true
    const out = applyMergePlan(plan, doc())

    expect(out.items[0].os.Server2012.execute).toBe(false)
    expect(out.osToAdd[0].buildStartsWith).toEqual([])
  })
})

describe('regression: duplicates within a single import are detected', () => {
  // buildMergePlan only compared against the target, so a .reg file setting the same
  // value twice imported it twice.
  it('flags the second occurrence and applies only one', () => {
    const plan = buildMergePlan(doc(), [svc('First', 'same'), svc('Second', 'same')])

    expect(plan.rows.map(r => r.status)).toEqual(['new', 'duplicate'])
    expect(plan.rows[1].notes).toContain('also in this import')
    expect(applyMergePlan(plan, doc()).items).toHaveLength(1)
  })

  it('catches it through the real .reg path too', () => {
    const src = [
      'Windows Registry Editor Version 5.00',
      '[HKEY_LOCAL_MACHINE\\SOFTWARE\\Test]',
      '"Flag"=dword:00000001',
      '"Flag"=dword:00000001'
    ].join('\n')
    const items = regEntriesToItems(parseReg(src).entries, { category: 'Imported', order: 100, os: { Windows11: OS_ON } }, 'dup.reg')

    expect(items).toHaveLength(2)
    const plan = buildMergePlan(doc(), items)
    expect(plan.counts.duplicate).toBe(1)
    expect(applyMergePlan(plan, doc()).items).toHaveLength(1)
  })
})

describe('regression: version stamps', () => {
  // The format comment once claimed properties the code did not have. These pin the
  // behaviour that actually ships.
  it('matches the stamp style already in Windows.xml', () => {
    expect(formatVersion(new Date(2026, 3, 29, 22, 30))).toBe('2026.429.2230')
  })

  it('never zero-pads, and allows a bare 0 for a midnight build', () => {
    expect(formatVersion(new Date(2026, 0, 1, 0, 0))).toBe('2026.101.0')
    expect(formatVersion(new Date(2026, 0, 1, 9, 7))).toBe('2026.101.907')
  })

  it('keeps every minute of a day distinct', () => {
    const seen = new Set<string>()
    for (let h = 0; h < 24; h++) for (let m = 0; m < 60; m++) seen.add(formatVersion(new Date(2026, 5, 9, h, m)))
    expect(seen.size).toBe(1440)
  })
})

describe('regression: Metadata survives a download', () => {
  // parseXml ignored <Metadata> and serializeXml never wrote it, so every edited
  // template silently lost its version.
  it('round-trips the real Windows.xml with its version intact', () => {
    const original = parseXml(windowsXml)
    expect(original.metadata).not.toBeNull()

    const reparsed = parseXml(serializeXml(original))
    expect(reparsed.metadata).toEqual(original.metadata)
    expect(reparsed.items).toHaveLength(original.items.length)
    expect(reparsed.supportedOs).toHaveLength(original.supportedOs.length)
  })

  it('keeps the descriptive fields when the version is re-stamped', () => {
    // doSave() rebuilds the metadata object; a plain literal there would silently drop
    // the id, name, author and tags a catalog is generated from.
    const original = parseXml(windowsXml)
    const prev = original.metadata!
    original.metadata = { ...prev, version: '2026.726.905' }

    const re = parseXml(serializeXml(original))
    expect(re.metadata!.version).toBe('2026.726.905')
    expect(re.metadata!.id).toBe(prev.id)
    expect(re.metadata!.name).toBe(prev.name)
    expect(re.metadata!.author).toBe(prev.author)
    expect(re.metadata!.tags).toEqual(prev.tags)
  })

  it('does not invent a Metadata block for a file that had none', () => {
    // Explicitly null, unlike the shared doc() helper which supplies metadata so other
    // fixtures are not flagged by the required-properties rule.
    const out = serializeXml({ ...doc([svc('A', 'a')]), metadata: null })
    expect(out).not.toContain('<Metadata>')
    expect(parseXml(out).metadata).toBeNull()
  })
})

describe('regression: empty registry values', () => {
  // "Name"="" is legal in a .reg file but the validator rejected every empty value,
  // which made a valid construct un-importable.
  it('accepts an empty String but still rejects an empty DWord', () => {
    const reg = (registryType: string, value: string): TemplateItem => ({
      ...svc('R', 'x'), type: 'Registry', typeRaw: 'Registry',
      payload: { type: 'Registry', hive: 'HKLM', path: 'SW\\T', name: 'V', action: 'SetValue', value, registryType }
    })
    const failed = (t: string, v: string) =>
      validate(doc([reg(t, v)])).errors.some(e => e.path.endsWith('/Value'))

    expect(failed('String', '')).toBe(false)
    expect(failed('DWord', '')).toBe(true)
    expect(failed('DWord', '0')).toBe(false)
  })

  it('imports one straight from a .reg file and validates clean', () => {
    const src = 'Windows Registry Editor Version 5.00\n[HKLM\\SOFTWARE\\T]\n"Blank"=""'
    const items = regEntriesToItems(parseReg(src).entries, { category: 'Imported', order: 100, os: { Windows11: OS_ON } }, 'e.reg')

    expect(items[0].payload).toMatchObject({ value: '', registryType: 'String' })
    expect(validate(doc(items)).errors).toHaveLength(0)
  })
})

describe('regression: merged output stays valid and serializable', () => {
  it('never leaves a dangling OS reference after a merge', () => {
    const target = doc([svc('Existing', 'keep')])
    const incoming = [svc('New', 'fresh', { Windows11: OS_ON, Server2012: OS_ON })]
    const out = applyMergePlan(buildMergePlan(target, incoming), target)

    const merged = doc([...target.items, ...out.items], [...target.supportedOs, ...out.osToAdd])
    expect(validate(merged).errors.filter(e => e.code === 'OS_MAPPING_UNKNOWN_TAG')).toHaveLength(0)
    expect(out.droppedOsTags).toEqual(['Server2012'])
    expect(parseXml(serializeXml(merged)).items).toHaveLength(2)
  })

  it('does not alias applied items back to the plan', () => {
    const plan = buildMergePlan(doc(), [svc('A', 'a')])
    const out = applyMergePlan(plan, doc())
    out.items[0].name = 'mutated'
    out.items[0].os.Windows11.execute = false

    expect(plan.rows[0].item.name).toBe('A')
    expect(plan.rows[0].item.os.Windows11.execute).toBe(true)
  })
})

describe('regression: .reg decoding', () => {
  // regedit writes UTF-16LE; reading it as UTF-8 yields NUL-interleaved garbage.
  it('decodes a UTF-16LE export through the buffer entry point', () => {
    const text = 'Windows Registry Editor Version 5.00\r\n[HKLM\\SOFTWARE\\T]\r\n"V"="x"\r\n'
    const bytes = new Uint8Array(text.length * 2 + 2)
    bytes[0] = 0xff; bytes[1] = 0xfe
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i)
      bytes[2 + i * 2] = c & 0xff
      bytes[3 + i * 2] = c >> 8
    }

    const result = parseRegBuffer(bytes.buffer)
    expect(result.encoding).toBe('utf-16le')
    expect(result.headerVersion).toBe('5.00')
    expect(result.entries[0]).toMatchObject({ hive: 'HKLM', path: 'SOFTWARE\\T', name: 'V', value: 'x' })
  })

  it('keeps 64-bit Qword precision that Number would lose', () => {
    const src = 'Windows Registry Editor Version 5.00\n[HKLM\\SW\\T]\n"Q"=hex(b):ef,cd,ab,89,67,45,23,01'
    expect(parseReg(src).entries[0].value).toBe('81985529216486895')
    expect(String(0x0123456789abcdef)).toBe('81985529216486900')   // the lossy path
  })
})
