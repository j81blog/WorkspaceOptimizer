import { describe, it, expect } from 'vitest'
import { itemKey, buildMergePlan, applyMergePlan } from '../../src/core/merge'
import { validate } from '../../src/core/validator'
import type { TemplateDocument, TemplateItem, OsDefinition, ItemPayload } from '../../src/core/types'

const W11: OsDefinition = { tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }
const W10: OsDefinition = { tag: 'Windows10', name: 'Windows 10', abbreviation: 'W10', isServerOs: false, buildStartsWith: ['19'] }

function item(overrides: Partial<TemplateItem> = {}): TemplateItem {
  return {
    id: crypto.randomUUID(), name: 'Item', description: '', type: 'Service', typeRaw: 'Service',
    category: 'General', order: 100, os: { Windows11: { execute: true, physical: true, virtual: true } },
    payload: { type: 'Service', name: 'svc', action: 'Disabled' },
    ...overrides
  }
}

function reg(over: Partial<Extract<ItemPayload, { type: 'Registry' }>> = {}): ItemPayload {
  return { type: 'Registry', hive: 'HKLM', path: 'SOFTWARE\\Test', name: 'Val', action: 'SetValue', value: '1', registryType: 'DWord', ...over }
}

function doc(items: TemplateItem[] = [], supportedOs: OsDefinition[] = [W11]): TemplateDocument {
  return { metadata: null, supportedOs, items }
}

describe('itemKey', () => {
  it('is case-insensitive and normalizes backslashes for Registry', () => {
    const a = item({ type: 'Registry', typeRaw: 'Registry', payload: reg({ path: 'SOFTWARE\\Test' }) })
    const b = item({ type: 'Registry', typeRaw: 'Registry', payload: reg({ path: 'software\\\\test\\', name: 'val' }) })
    expect(itemKey(a)).toBe(itemKey(b))
  })

  it('is stable across name, order and category changes', () => {
    const a = item({ name: 'One', order: 10, category: 'A' })
    const b = item({ name: 'Two', order: 90, category: 'B' })
    expect(itemKey(a)).toBe(itemKey(b))
  })

  it('distinguishes payload types with the same inner name', () => {
    const svc = item({ payload: { type: 'Service', name: 'x', action: 'Disabled' } })
    const app = item({ type: 'StoreApp', typeRaw: 'StoreApp', payload: { type: 'StoreApp', name: 'x' } })
    expect(itemKey(svc)).not.toBe(itemKey(app))
  })

  it('gives every Unknown item a distinct key', () => {
    const a = item({ type: 'Unknown', typeRaw: 'Weird', payload: { type: 'Unknown' } })
    const b = item({ type: 'Unknown', typeRaw: 'Weird', payload: { type: 'Unknown' } })
    expect(itemKey(a)).not.toBe(itemKey(b))
  })
})

describe('buildMergePlan: statuses', () => {
  it('marks an unseen target as new and selects it', () => {
    const plan = buildMergePlan(doc(), [item({ payload: { type: 'Service', name: 'fresh', action: 'Disabled' } })])
    expect(plan.rows[0].status).toBe('new')
    expect(plan.rows[0].selected).toBe(true)
  })

  it('marks an identical payload as duplicate and leaves it unselected', () => {
    const existing = item()
    const plan = buildMergePlan(doc([existing]), [item({ name: 'Renamed' })])
    expect(plan.rows[0].status).toBe('duplicate')
    expect(plan.rows[0].selected).toBe(false)
  })

  it('marks a same-target different-payload item as conflict and leaves it unselected', () => {
    const existing = item({ type: 'Registry', typeRaw: 'Registry', payload: reg({ value: '1' }) })
    const incoming = item({ type: 'Registry', typeRaw: 'Registry', payload: reg({ value: '0' }) })
    const plan = buildMergePlan(doc([existing]), [incoming])
    expect(plan.rows[0].status).toBe('conflict')
    expect(plan.rows[0].selected).toBe(false)
    expect(plan.rows[0].existing).toBe(existing)
  })

  it('counts match the row statuses', () => {
    const existing = item()
    const plan = buildMergePlan(doc([existing]), [
      item(),                                                                   // duplicate
      item({ payload: { type: 'Service', name: 'other', action: 'Disabled' } }) // new
    ])
    expect(plan.counts).toEqual({ new: 1, duplicate: 1, conflict: 0 })
  })

  it('notes a recursive registry delete', () => {
    const incoming = item({ type: 'Registry', typeRaw: 'Registry', payload: reg({ action: 'DeleteKeyRecursively' }) })
    expect(buildMergePlan(doc(), [incoming]).rows[0].notes).toContain('recursive delete')
  })
})

describe('buildMergePlan: missing OS tags', () => {
  it('reports an unknown tag with its definition when the source carries one', () => {
    const incoming = item({ os: { Windows10: { execute: true, physical: true, virtual: true } } })
    const plan = buildMergePlan(doc(), [incoming], [W10])
    expect(plan.missingOs).toHaveLength(1)
    expect(plan.missingOs[0].tag).toBe('Windows10')
    expect(plan.missingOs[0].definition).toEqual(W10)
    expect(plan.missingOs[0].accepted).toBe(false)
  })

  it('offers a stub definition when the source carries none', () => {
    const incoming = item({ os: { Server2016: { execute: true, physical: true, virtual: true } } })
    const missing = buildMergePlan(doc(), [incoming]).missingOs[0]

    expect(missing.complete).toBe(false)
    expect(missing.definition).toMatchObject({ tag: 'Server2016', buildStartsWith: [] })
  })

  it('marks a carried definition as complete', () => {
    const incoming = item({ os: { Windows10: { execute: true, physical: true, virtual: true } } })
    const missing = buildMergePlan(doc(), [incoming], [W10]).missingOs[0]

    expect(missing.complete).toBe(true)
    expect(missing.definition).toEqual(W10)
  })

  it('notes an item that would run on no OS at all', () => {
    const incoming = item({ os: {} })
    expect(buildMergePlan(doc(), [incoming]).rows[0].notes).toContain('will not run on any OS')
  })

  it('drops an unaccepted tag but does not call the item dead, it can be added', () => {
    const incoming = item({ os: { Server2012: { execute: true, physical: true, virtual: true } } })
    const plan = buildMergePlan(doc(), [incoming])

    expect(plan.rows[0].notes).not.toContain('will not run on any OS')
    expect(Object.keys(applyMergePlan(plan, doc()).items[0].os)).toEqual([])
  })

  it('keeps the mapping when a stub OS is accepted, but disabled', () => {
    const incoming = item({ os: { Server2012: { execute: true, physical: true, virtual: true } } })
    const plan = buildMergePlan(doc(), [incoming])
    plan.missingOs[0].accepted = true
    const out = applyMergePlan(plan, doc())

    expect(out.osToAdd.map(o => o.tag)).toEqual(['Server2012'])
    // Present so the user can see and fix it, but inert until builds are supplied.
    expect(out.items[0].os.Server2012).toEqual({ execute: false, physical: true, virtual: true })
  })

  it('leaves execute alone when the accepted OS came with a full definition', () => {
    const incoming = item({ os: { Windows10: { execute: true, physical: true, virtual: true } } })
    const plan = buildMergePlan(doc(), [incoming], [W10])
    plan.missingOs[0].accepted = true

    expect(applyMergePlan(plan, doc()).items[0].os.Windows10.execute).toBe(true)
  })

  it('does not note an item whose missing tag can be accepted', () => {
    const incoming = item({ os: { Windows10: { execute: true, physical: true, virtual: true } } })
    expect(buildMergePlan(doc(), [incoming], [W10]).rows[0].notes).not.toContain('will not run on any OS')
  })
})

describe('buildMergePlan: duplicates within the incoming set', () => {
  const dup = (name: string) => item({ name, payload: { type: 'Service', name: 'same', action: 'Disabled' } })

  it('marks a repeat of an earlier incoming item as duplicate', () => {
    const plan = buildMergePlan(doc(), [dup('First'), dup('Second')])
    expect(plan.rows.map(r => r.status)).toEqual(['new', 'duplicate'])
    expect(plan.rows[1].notes).toContain('also in this import')
    expect(applyMergePlan(plan, doc()).items).toHaveLength(1)
  })

  it('marks a differing repeat as a conflict rather than a duplicate', () => {
    const a = item({ name: 'A', payload: { type: 'Service', name: 'same', action: 'Disabled' } })
    const b = item({ name: 'B', payload: { type: 'Service', name: 'same', action: 'Manual' } })
    const plan = buildMergePlan(doc(), [a, b])
    expect(plan.rows.map(r => r.status)).toEqual(['new', 'conflict'])
  })

  it('still prefers the existing target over an earlier incoming item', () => {
    const existing = item({ name: 'Existing', payload: { type: 'Service', name: 'same', action: 'Disabled' } })
    const plan = buildMergePlan(doc([existing]), [dup('First'), dup('Second')])
    expect(plan.rows[0].existing).toBe(existing)
    expect(plan.rows.map(r => r.status)).toEqual(['duplicate', 'duplicate'])
  })
})

describe('applyMergePlan', () => {
  it('excludes unselected rows', () => {
    const plan = buildMergePlan(doc(), [item(), item({ payload: { type: 'Service', name: 'b', action: 'Manual' } })])
    plan.rows[1].selected = false
    expect(applyMergePlan(plan, doc()).items).toHaveLength(1)
  })

  it('keeps accepted OS tags and returns the definition to add', () => {
    const incoming = item({ os: { Windows10: { execute: true, physical: true, virtual: true } } })
    const plan = buildMergePlan(doc(), [incoming], [W10])
    plan.missingOs[0].accepted = true
    const out = applyMergePlan(plan, doc())
    expect(out.items[0].os).toHaveProperty('Windows10')
    expect(out.osToAdd).toEqual([W10])
    expect(out.droppedOsTags).toEqual([])
  })

  it('prunes unaccepted tags and reports them', () => {
    const incoming = item({ os: { Windows11: { execute: true, physical: true, virtual: true }, Server2016: { execute: true, physical: true, virtual: true } } })
    const out = applyMergePlan(buildMergePlan(doc(), [incoming]), doc())
    expect(Object.keys(out.items[0].os)).toEqual(['Windows11'])
    expect(out.droppedOsTags).toEqual(['Server2016'])
  })

  it('carries an order edited in the preview through to the applied items', () => {
    // The table writes straight onto plan.rows[].item, so the clone must pick it up.
    const plan = buildMergePlan(doc(), [item({ name: 'A' }), item({ name: 'B', payload: { type: 'Service', name: 'b', action: 'Manual' } })])
    plan.rows[0].item.order = 60
    plan.rows[1].item.order = 90

    expect(applyMergePlan(plan, doc()).items.map(i => i.order)).toEqual([60, 90])
  })

  it('returns deep clones', () => {
    const plan = buildMergePlan(doc(), [item()])
    const out = applyMergePlan(plan, doc())
    out.items[0].name = 'mutated'
    out.items[0].os.Windows11.execute = false
    expect(plan.rows[0].item.name).toBe('Item')
    expect(plan.rows[0].item.os.Windows11.execute).toBe(true)
  })

  it('produces no OS_MAPPING_UNKNOWN_TAG errors on the dropped path', () => {
    const target = doc()
    const incoming = item({ os: { Windows11: { execute: true, physical: true, virtual: true }, Server2016: { execute: true, physical: true, virtual: true } } })
    const out = applyMergePlan(buildMergePlan(target, [incoming]), target)
    const merged = doc([...target.items, ...out.items], [...target.supportedOs, ...out.osToAdd])
    expect(validate(merged).errors.filter(e => e.code === 'OS_MAPPING_UNKNOWN_TAG')).toHaveLength(0)
  })

  it('produces no OS_MAPPING_UNKNOWN_TAG errors on the accepted path', () => {
    const target = doc()
    const incoming = item({ os: { Windows10: { execute: true, physical: true, virtual: true } } })
    const plan = buildMergePlan(target, [incoming], [W10])
    plan.missingOs[0].accepted = true
    const out = applyMergePlan(plan, target)
    const merged = doc([...target.items, ...out.items], [...target.supportedOs, ...out.osToAdd])
    expect(validate(merged).errors.filter(e => e.code === 'OS_MAPPING_UNKNOWN_TAG')).toHaveLength(0)
  })
})
