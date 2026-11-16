import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { nextTick } from 'vue'
import { documentStore } from '../../src/store/document'
import { loadDraft, clearDraft, startAutosave } from '../../src/store/draft'
import { parseXml } from '../../src/core/parser'
import type { TemplateDocument, TemplateMetadata } from '../../src/core/types'

const doc = (): TemplateDocument => ({
  metadata: null,
  supportedOs: [{ tag: 'W11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }],
  items: []
})
const meta: TemplateMetadata = { version: '', schemaVersion: '1', id: 'x', name: 'n', description: '', author: '', category: '', tags: [] }

let started = false

beforeEach(() => {
  vi.useFakeTimers()
  localStorage.clear()
  documentStore.load(doc(), 'a.xml')
  if (!started) { startAutosave(); started = true }
})
afterEach(() => { clearDraft(); vi.useRealTimers() })

describe('autosave', () => {
  it('writes a draft about a second after an edit', async () => {
    documentStore.addItem({ id: '1', name: 'Svc', description: '', type: 'Service', typeRaw: 'Service', category: 'C', order: 1, os: {}, payload: { type: 'Service', name: 's', action: 'Disabled' } })
    await nextTick()
    vi.advanceTimersByTime(500)
    expect(loadDraft()).toBeNull()
    vi.advanceTimersByTime(600)
    const d = loadDraft()
    expect(d?.filename).toBe('a.xml')
    expect(parseXml(d!.xml).items[0].name).toBe('Svc')
  })

  it('clears the draft when the document is no longer dirty', async () => {
    documentStore.setMetadata(meta)
    await nextTick()
    vi.advanceTimersByTime(1100)
    expect(loadDraft()).not.toBeNull()
    documentStore.dirty = false
    await nextTick()
    vi.advanceTimersByTime(1100)
    expect(loadDraft()).toBeNull()
  })

  it('survives storage that throws', async () => {
    const spy = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('quota') })
    documentStore.setMetadata(meta)
    await nextTick()
    expect(() => vi.advanceTimersByTime(1100)).not.toThrow()
    spy.mockRestore()
  })

  it('clearDraft cancels a pending save', async () => {
    documentStore.setMetadata(meta)
    await nextTick()
    clearDraft()
    vi.advanceTimersByTime(1500)
    expect(loadDraft()).toBeNull()
  })
})
