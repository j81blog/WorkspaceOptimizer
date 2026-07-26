import { describe, it, expect } from 'vitest'
import { validate } from '../../src/core/validator'
import type { TemplateDocument, TemplateItem } from '../../src/core/types'

function makeItem(overrides: Partial<TemplateItem> = {}): TemplateItem {
  return {
    id: 'test-1', name: 'My Item', description: '', type: 'Service', typeRaw: 'Service',
    category: 'General', order: 100, os: {},
    payload: { type: 'Service', name: 'svc', action: 'Disabled' },
    ...overrides
  }
}

/** Complete metadata, so a fixture is only invalid for the reason under test. */
function makeMeta() {
  return {
    version: '2026.1.1', schemaVersion: '1', id: 'test-id',
    name: 'Test Template', description: 'For tests.', author: 'Tester',
    category: '', tags: []
  }
}

function makeDoc(overrides: Partial<TemplateDocument> = {}): TemplateDocument {
  return {
    metadata: makeMeta(),
    supportedOs: [{ tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['21'] }],
    items: [makeItem()],
    ...overrides
  }
}

it('errors on empty name', () => {
  expect(validate(makeDoc({ items: [makeItem({ name: '' })] })).errors.some(e => e.code === 'ITEM_NAME_REQUIRED')).toBe(true)
})

it('errors on empty category', () => {
  expect(validate(makeDoc({ items: [makeItem({ category: '' })] })).errors.some(e => e.code === 'ITEM_CATEGORY_REQUIRED')).toBe(true)
})

it('errors on order > 99999', () => {
  expect(validate(makeDoc({ items: [makeItem({ order: 100000 })] })).errors.some(e => e.code === 'ITEM_ORDER_RANGE')).toBe(true)
})

it('passes on order 0', () => {
  expect(validate(makeDoc({ items: [makeItem({ order: 0 })] })).errors.some(e => e.code === 'ITEM_ORDER_RANGE')).toBe(false)
})

it('errors on unknown OS mapping tag', () => {
  expect(validate(makeDoc({ items: [makeItem({ os: { UnknownOS: { execute: true, physical: true, virtual: false } } })] }))
    .errors.some(e => e.code === 'OS_MAPPING_UNKNOWN_TAG')).toBe(true)
})

it('errors on duplicate OS tag', () => {
  const os = { tag: 'Windows11', name: 'W11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['21'] }
  expect(validate(makeDoc({ supportedOs: [os, { ...os, name: 'Dup' }] })).errors.some(e => e.code === 'OS_TAG_DUPLICATE')).toBe(true)
})

it('errors on missing Registry path', () => {
  expect(validate(makeDoc({ items: [makeItem({
    type: 'Registry', typeRaw: 'Registry',
    payload: { type: 'Registry', hive: 'HKLM', path: '', name: 'v', action: 'SetValue', value: '1', registryType: 'DWord' }
  })] })).errors.some(e => e.code === 'FIELD_REQUIRED' && e.path.includes('Path'))).toBe(true)
})

it('errors on invalid DWord value', () => {
  expect(validate(makeDoc({ items: [makeItem({
    type: 'Registry', typeRaw: 'Registry',
    payload: { type: 'Registry', hive: 'HKLM', path: 'SW\\Test', name: 'v', action: 'SetValue', value: 'notanumber', registryType: 'DWord' }
  })] })).errors.some(e => e.code === 'FIELD_FORMAT')).toBe(true)
})

it('returns no errors for a valid document', () => {
  expect(validate(makeDoc()).errors).toHaveLength(0)
})

describe('registry empty values', () => {
  const reg = (registryType: string, value: string) => makeDoc({
    items: [makeItem({
      type: 'Registry', typeRaw: 'Registry',
      payload: { type: 'Registry', hive: 'HKLM', path: 'SW\\Test', name: 'v', action: 'SetValue', value, registryType }
    })]
  })
  const missing = (d: ReturnType<typeof reg>) =>
    validate(d).errors.some(e => e.code === 'FIELD_REQUIRED' && e.path.endsWith('/Value'))

  it.each(['String', 'ExpandString', 'MultiString'])('allows an empty %s value', (t) => {
    expect(missing(reg(t, ''))).toBe(false)
  })

  it.each(['DWord', 'Qword', 'Binary'])('still requires a value for %s', (t) => {
    expect(missing(reg(t, ''))).toBe(true)
  })

  it('still accepts "0" for DWord', () => {
    expect(missing(reg('DWord', '0'))).toBe(false)
  })
})

describe('template properties', () => {
  const meta = (over: Record<string, unknown> = {}) => makeDoc({ metadata: { ...makeMeta(), ...over } })
  const codes = (d: ReturnType<typeof makeDoc>) =>
    validate(d).errors.filter(e => e.code === 'META_REQUIRED').map(e => e.path)

  it.each(['name', 'description', 'author'])('requires %s', (field) => {
    expect(codes(meta({ [field]: '' }))).toHaveLength(1)
    expect(codes(meta({ [field]: '   ' }))).toHaveLength(1)   // whitespace is not a value
  })

  it('does not require category or tags', () => {
    expect(codes(meta({ category: '', tags: [] }))).toHaveLength(0)
  })

  it('reports every missing field at once', () => {
    expect(codes(meta({ name: '', description: '', author: '' }))).toEqual(
      ['/Metadata/Name', '/Metadata/Description', '/Metadata/Author']
    )
  })

  it('flags all three when there is no metadata block at all', () => {
    expect(codes(makeDoc({ metadata: null }))).toHaveLength(3)
  })

  it('blocks the download, since hasErrors gates it', () => {
    expect(validate(meta({ name: '' })).errors.length).toBeGreaterThan(0)
    expect(validate(meta()).errors).toHaveLength(0)
  })
})
