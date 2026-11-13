import { watch } from 'vue'
import { documentStore } from './document'
import { serializeXml } from '../core/serializer'

const KEY = 'wo-draft'
const DELAY_MS = 1000

export interface Draft {
  xml: string
  filename: string
  savedAt: number
}

let timer: ReturnType<typeof setTimeout> | undefined

// Storage can be unavailable (private mode, blocked site data) or full. Autosave is a
// convenience, so every access swallows its failure.
export function loadDraft(): Draft | null {
  try {
    const d = JSON.parse(localStorage.getItem(KEY) ?? 'null')
    return d && typeof d.xml === 'string' ? d : null
  } catch { return null }
}

/** Also cancels a pending save, so a draft cannot reappear after a download. */
export function clearDraft(): void {
  clearTimeout(timer)
  try { localStorage.removeItem(KEY) } catch { /* nothing to clean up */ }
}

function flush(): void {
  const doc = documentStore.document
  if (!doc || !documentStore.dirty) { clearDraft(); return }
  try {
    const draft: Draft = { xml: serializeXml(doc), filename: documentStore.filename, savedAt: Date.now() }
    localStorage.setItem(KEY, JSON.stringify(draft))
  } catch { /* quota exceeded or storage unavailable */ }
}

/** Keeps a draft of unsaved work. A document with no unsaved changes has no draft. */
export function startAutosave(): void {
  watch(
    [() => documentStore.document, () => documentStore.dirty, () => documentStore.filename],
    () => {
      clearTimeout(timer)
      timer = setTimeout(flush, DELAY_MS)
    },
    { deep: true }
  )
}
