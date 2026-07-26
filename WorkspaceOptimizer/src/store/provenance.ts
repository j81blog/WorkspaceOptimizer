import { reactive } from 'vue'
import type { ImportSource } from '../core/types'

/**
 * Tracks which items came from an external source (the marketplace or a .reg file).
 *
 * This is deliberately kept OUT of TemplateItem and out of the XML: it exists only to
 * warn the user on download that a template contains content they did not author.
 * Keeping it in a side store makes it structurally impossible for it to reach the
 * serializer.
 *
 * Session-only, never persisted.
 */
export const provenanceStore = reactive({
  /** itemId -> source id */
  byItem: {} as Record<string, string>,
  /** source id -> descriptor */
  sources: {} as Record<string, ImportSource>,

  get hasImports(): boolean {
    return Object.keys(this.byItem).length > 0
  },

  /** Counts grouped by source, largest first. Drives the download warning. */
  get summary(): Array<{ source: ImportSource; count: number }> {
    const counts: Record<string, number> = {}
    for (const sourceId of Object.values(this.byItem)) {
      counts[sourceId] = (counts[sourceId] ?? 0) + 1
    }
    return Object.entries(counts)
      .filter(([id]) => this.sources[id])
      .map(([id, count]) => ({ source: this.sources[id], count }))
      .sort((a, b) => b.count - a.count)
  },

  record(itemIds: string[], source: ImportSource) {
    if (itemIds.length === 0) return
    this.sources[source.id] = source
    for (const id of itemIds) this.byItem[id] = source.id
  },

  /**
   * Forget one item. Called when an item is deleted so the counts stay honest.
   * Note that duplicating an item does NOT copy provenance. A user-duplicated item
   * is user-authored.
   */
  forget(itemId: string) {
    const sourceId = this.byItem[itemId]
    if (!sourceId) return
    delete this.byItem[itemId]
    // Drop the descriptor once nothing references it any more.
    if (!Object.values(this.byItem).includes(sourceId)) delete this.sources[sourceId]
  },

  clear() {
    this.byItem = {}
    this.sources = {}
  }
})

let regCounter = 0

/** Distinct source id per .reg import, so importing the same file twice stays separate. */
export function nextRegSourceId(filename: string): string {
  return `reg:${filename}#${++regCounter}`
}
