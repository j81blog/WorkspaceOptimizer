import { reactive } from 'vue'
import { validate } from '../core/validator'
import { provenanceStore } from './provenance'
import type { TemplateDocument, TemplateItem, TemplateMetadata, OsDefinition, ValidationResult } from '../core/types'

export const documentStore = reactive({
  document: null as TemplateDocument | null,
  dirty: false,
  filename: 'Windows.xml',

  get validationResult(): ValidationResult {
    if (!this.document) return { errors: [], warnings: [] }
    return validate(this.document)
  },

  get hasErrors(): boolean {
    return this.validationResult.errors.length > 0
  },

  load(doc: TemplateDocument, filename: string) {
    this.document = doc
    this.dirty = false
    this.filename = filename
    provenanceStore.clear()
  },

  /**
   * Start an empty document, e.g. when importing with nothing loaded. It gets an Id
   * immediately so the template is identifiable even if the user never opens the
   * Properties dialog; the descriptive fields stay empty and are flagged by the
   * validator until filled in.
   */
  newEmpty(supportedOs: OsDefinition[], filename: string) {
    this.load({
      metadata: {
        version: '', schemaVersion: '1', id: crypto.randomUUID(),
        name: '', description: '', author: '', category: '', tags: []
      },
      supportedOs,
      items: []
    }, filename)
  },

  addItem(item: TemplateItem) {
    this.document?.items.push(item)
    this.dirty = true
  },

  /** Bulk add, one reactivity flush instead of one per item. */
  addItems(items: TemplateItem[]) {
    if (!this.document || items.length === 0) return
    this.document.items.push(...items)
    this.dirty = true
  },

  /** Replace the template's descriptive metadata (the Properties dialog). */
  setMetadata(meta: TemplateMetadata) {
    if (!this.document) return
    this.document.metadata = meta
    this.dirty = true
  },

  /**
   * Append a single OS definition. Distinct from setOsDefinitions, which prunes
   * unknown tags from every item and so cannot be used mid-import.
   */
  addOsDefinition(os: OsDefinition) {
    if (!this.document) return
    if (this.document.supportedOs.some(o => o.tag === os.tag)) return
    this.document.supportedOs.push(os)
    this.dirty = true
  },

  updateItem(id: string, patch: Partial<TemplateItem>) {
    const item = this.document?.items.find(i => i.id === id)
    if (item) Object.assign(item, patch)
    this.dirty = true
  },

  deleteItem(id: string) {
    if (!this.document) return
    this.document.items = this.document.items.filter(i => i.id !== id)
    provenanceStore.forget(id)
    this.dirty = true
  },

  setOsDefinitions(osList: OsDefinition[]) {
    if (!this.document) return
    const validTags = new Set(osList.map(o => o.tag))
    for (const item of this.document.items) {
      for (const tag of Object.keys(item.os)) {
        if (!validTags.has(tag)) delete item.os[tag]
      }
    }
    this.document.supportedOs = osList
    this.dirty = true
  }
})
