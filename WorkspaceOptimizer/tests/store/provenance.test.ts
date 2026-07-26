import { describe, it, expect, beforeEach } from 'vitest'
import { provenanceStore, nextRegSourceId } from '../../src/store/provenance'
import type { ImportSource } from '../../src/core/types'

/**
 * Provenance drives the pre-download warning, so the invariant that matters is that
 * counts stay honest as items are added and removed, and that nothing leaks between
 * documents.
 */

const mp = (id: string, label: string, origin = 'raw.githubusercontent.com'): ImportSource =>
  ({ id, kind: 'marketplace', label, origin })

beforeEach(() => provenanceStore.clear())

describe('recording', () => {
  it('starts empty', () => {
    expect(provenanceStore.hasImports).toBe(false)
    expect(provenanceStore.summary).toEqual([])
  })

  it('records items against a source', () => {
    provenanceStore.record(['a', 'b'], mp('mp:x', 'Telemetry'))
    expect(provenanceStore.hasImports).toBe(true)
    expect(provenanceStore.summary).toEqual([
      { source: mp('mp:x', 'Telemetry'), count: 2 }
    ])
  })

  it('ignores an empty item list rather than registering a phantom source', () => {
    provenanceStore.record([], mp('mp:x', 'Telemetry'))
    expect(provenanceStore.hasImports).toBe(false)
    expect(provenanceStore.summary).toEqual([])
  })

  it('groups by source and orders by count, largest first', () => {
    provenanceStore.record(['a'], mp('mp:small', 'Small'))
    provenanceStore.record(['b', 'c', 'd'], mp('reg:big', 'big.reg', ''))
    expect(provenanceStore.summary.map(s => [s.source.label, s.count]))
      .toEqual([['big.reg', 3], ['Small', 1]])
  })

  it('re-recording an item moves it to the newer source', () => {
    provenanceStore.record(['a'], mp('mp:one', 'One'))
    provenanceStore.record(['a'], mp('mp:two', 'Two'))
    expect(provenanceStore.summary).toEqual([{ source: mp('mp:two', 'Two'), count: 1 }])
  })
})

describe('forgetting', () => {
  it('decrements the count when an imported item is deleted', () => {
    provenanceStore.record(['a', 'b'], mp('mp:x', 'X'))
    provenanceStore.forget('a')
    expect(provenanceStore.summary[0].count).toBe(1)
  })

  it('drops the source entirely once its last item is gone', () => {
    provenanceStore.record(['a'], mp('mp:x', 'X'))
    provenanceStore.forget('a')
    expect(provenanceStore.hasImports).toBe(false)
    expect(provenanceStore.summary).toEqual([])
    expect(provenanceStore.sources['mp:x']).toBeUndefined()
  })

  it('ignores an unknown item id', () => {
    provenanceStore.record(['a'], mp('mp:x', 'X'))
    provenanceStore.forget('never-seen')
    expect(provenanceStore.summary[0].count).toBe(1)
  })

  it('leaves other sources untouched', () => {
    provenanceStore.record(['a'], mp('mp:one', 'One'))
    provenanceStore.record(['b'], mp('mp:two', 'Two'))
    provenanceStore.forget('a')
    expect(provenanceStore.summary.map(s => s.source.id)).toEqual(['mp:two'])
  })
})

describe('clearing', () => {
  it('removes every item and source', () => {
    provenanceStore.record(['a', 'b'], mp('mp:x', 'X'))
    provenanceStore.clear()
    expect(provenanceStore.hasImports).toBe(false)
    expect(provenanceStore.sources).toEqual({})
    expect(provenanceStore.byItem).toEqual({})
  })
})

describe('nextRegSourceId', () => {
  it('gives the same file a distinct id per import, so two imports stay separate', () => {
    const first = nextRegSourceId('tweaks.reg')
    const second = nextRegSourceId('tweaks.reg')
    expect(first).not.toBe(second)
    expect(first).toMatch(/^reg:tweaks\.reg#\d+$/)

    provenanceStore.record(['a'], { id: first, kind: 'reg', label: 'tweaks.reg', origin: '' })
    provenanceStore.record(['b'], { id: second, kind: 'reg', label: 'tweaks.reg', origin: '' })
    expect(provenanceStore.summary).toHaveLength(2)
  })
})
