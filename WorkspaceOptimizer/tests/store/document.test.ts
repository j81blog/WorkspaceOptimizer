import { describe, it, expect, beforeEach } from 'vitest'
import { documentStore } from '../../src/store/document'
import { provenanceStore } from '../../src/store/provenance'
import type { TemplateItem, OsDefinition } from '../../src/core/types'

/**
 * Covers the store methods added for importing, and the wiring between the document
 * and provenance stores, since deleting an imported item has to decrement the download
 * warning, and loading a new document has to reset it.
 */

const W11: OsDefinition = { tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }
const W10: OsDefinition = { tag: 'Windows10', name: 'Windows 10', abbreviation: 'W10', isServerOs: false, buildStartsWith: ['19'] }

function item(id: string, os: Record<string, { execute: boolean; physical: boolean; virtual: boolean }> = {}): TemplateItem {
  return {
    id, name: `Item ${id}`, description: '', type: 'Service', typeRaw: 'Service',
    category: 'General', order: 100, os,
    payload: { type: 'Service', name: `svc-${id}`, action: 'Disabled' }
  }
}

beforeEach(() => {
  documentStore.load({ metadata: null, supportedOs: [W11], items: [] }, 'test.xml')
})

describe('newEmpty', () => {
  it('creates an empty document with the given OS list', () => {
    documentStore.newEmpty([W11, W10], 'Untitled.xml')
    expect(documentStore.document!.supportedOs).toEqual([W11, W10])
    expect(documentStore.document!.items).toEqual([])
    expect(documentStore.filename).toBe('Untitled.xml')
    expect(documentStore.dirty).toBe(false)
  })

  it('gives a new document an Id straight away, but no descriptive fields', () => {
    // The template is identifiable even if Properties is never opened; the empty
    // fields are what the validator flags.
    documentStore.newEmpty([W11], 'Untitled.xml')
    const meta = documentStore.document!.metadata!

    expect(meta.id).toMatch(/^[0-9a-f-]{36}$/)
    expect(meta.name).toBe('')
    expect(meta.description).toBe('')
    expect(meta.author).toBe('')
  })

  it('clears provenance from the previous document', () => {
    documentStore.addItems([item('a')])
    provenanceStore.record(['a'], { id: 'mp:x', kind: 'marketplace', label: 'X', origin: 'example.com' })
    expect(provenanceStore.hasImports).toBe(true)

    documentStore.newEmpty([W11], 'Untitled.xml')
    expect(provenanceStore.hasImports).toBe(false)
  })
})

describe('addItems', () => {
  it('appends every item and marks the document dirty', () => {
    documentStore.addItems([item('a'), item('b')])
    expect(documentStore.document!.items.map(i => i.id)).toEqual(['a', 'b'])
    expect(documentStore.dirty).toBe(true)
  })

  it('is a no-op for an empty list', () => {
    documentStore.addItems([])
    expect(documentStore.document!.items).toHaveLength(0)
    expect(documentStore.dirty).toBe(false)
  })

  it('does nothing when no document is loaded', () => {
    documentStore.document = null
    expect(() => documentStore.addItems([item('a')])).not.toThrow()
  })
})

describe('addOsDefinition', () => {
  it('appends a new OS and marks the document dirty', () => {
    documentStore.addOsDefinition(W10)
    expect(documentStore.document!.supportedOs.map(o => o.tag)).toEqual(['Windows11', 'Windows10'])
    expect(documentStore.dirty).toBe(true)
  })

  it('ignores a tag that already exists', () => {
    documentStore.addOsDefinition({ ...W11, name: 'Renamed' })
    expect(documentStore.document!.supportedOs).toHaveLength(1)
    expect(documentStore.document!.supportedOs[0].name).toBe('Windows 11')
    expect(documentStore.dirty).toBe(false)
  })

  it('does not prune existing item OS mappings, unlike setOsDefinitions', () => {
    // The distinction matters: setOsDefinitions strips unknown tags from every item,
    // which would defeat adding an OS partway through an import.
    documentStore.addItems([item('a', { Windows10: { execute: true, physical: true, virtual: true } })])
    documentStore.addOsDefinition(W10)
    expect(Object.keys(documentStore.document!.items[0].os)).toEqual(['Windows10'])
  })
})

describe('deleteItem and provenance', () => {
  it('forgets provenance for the deleted item', () => {
    documentStore.addItems([item('a'), item('b')])
    provenanceStore.record(['a', 'b'], { id: 'mp:x', kind: 'marketplace', label: 'X', origin: 'example.com' })

    documentStore.deleteItem('a')
    expect(provenanceStore.summary[0].count).toBe(1)

    documentStore.deleteItem('b')
    expect(provenanceStore.hasImports).toBe(false)
  })

  it('leaves provenance alone when a non-imported item is deleted', () => {
    documentStore.addItems([item('a'), item('b')])
    provenanceStore.record(['a'], { id: 'mp:x', kind: 'marketplace', label: 'X', origin: 'example.com' })

    documentStore.deleteItem('b')
    expect(provenanceStore.summary[0].count).toBe(1)
  })
})

describe('load', () => {
  it('resets dirty and clears provenance', () => {
    documentStore.addItems([item('a')])
    provenanceStore.record(['a'], { id: 'mp:x', kind: 'marketplace', label: 'X', origin: 'example.com' })

    documentStore.load({ metadata: null, supportedOs: [W11], items: [] }, 'other.xml')
    expect(documentStore.dirty).toBe(false)
    expect(documentStore.filename).toBe('other.xml')
    expect(provenanceStore.hasImports).toBe(false)
  })
})
