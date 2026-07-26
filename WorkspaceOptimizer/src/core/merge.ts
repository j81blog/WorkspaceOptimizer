import type {
  TemplateDocument, TemplateItem, OsDefinition, MergeStatus
} from './types'

/**
 * Merging incoming items (from a marketplace snippet or a .reg import) into the
 * loaded template.
 *
 * Everything here is pure: buildMergePlan produces a plan, the dialog mutates the
 * plan's `selected` / `accepted` flags in place, and applyMergePlan reads the final
 * state and returns deep clones. Store mutation happens in App.vue, never here.
 */

export interface MergeRow {
  key: string
  status: MergeStatus
  item: TemplateItem              // the candidate; already carries a fresh uuid
  existing: TemplateItem | null   // the matched item, for duplicate/conflict
  selected: boolean
  notes: string[]
}

export interface MissingOs {
  tag: string
  /**
   * Definition to add if accepted. When the source carried one this is it; otherwise
   * it is a stub built from the tag alone, with no build numbers.
   */
  definition: OsDefinition
  /** False when the definition is a stub the user must complete in Manage OS. */
  complete: boolean
  accepted: boolean
}

export interface MergePlan {
  rows: MergeRow[]
  missingOs: MissingOs[]
  /** Snapshot of the initial statuses. The live selected-count is computed in the UI. */
  counts: { new: number; duplicate: number; conflict: number }
}

export interface MergeResult {
  items: TemplateItem[]      // deep-cloned, OS keys pruned
  osToAdd: OsDefinition[]
  droppedOsTags: string[]
}

/** Collapse repeated backslashes and trim leading/trailing ones. */
function normPath(p: string): string {
  return p.replace(/\\+/g, '\\').replace(/^\\|\\$/g, '').toLowerCase()
}

/**
 * Stable identity for what an item *targets*. Deliberately excludes name, category
 * and order: users rename freely, and two items that write the same registry value
 * are the same target regardless of what they are called.
 */
export function itemKey(item: TemplateItem): string {
  const p = item.payload
  switch (p.type) {
    case 'Registry':
      return `registry|${p.hive.toLowerCase()}|${normPath(p.path)}|${p.name.toLowerCase()}`
    case 'Service':
      return `service|${p.name.toLowerCase()}`
    case 'ScheduledTask':
      return `scheduledtask|${normPath(p.path)}|${p.name.toLowerCase()}`
    case 'StoreApp':
      return `storeapp|${p.name.toLowerCase()}`
    case 'FileFolder':
      return `filefolder|${normPath(p.path)}`
    case 'PowerShell':
      // Scripts have no natural target; fall back to the display name.
      return `powershell|${item.name.toLowerCase()}`
    default:
      // Unknown payloads are never equal to anything, so they always count as new.
      return `unknown|${item.id}`
  }
}

/** Compare payloads only. The name/category/order/os differences do not make a conflict. */
function samePayload(a: TemplateItem, b: TemplateItem): boolean {
  return JSON.stringify(a.payload) === JSON.stringify(b.payload)
}

export function buildMergePlan(
  target: TemplateDocument,
  incoming: TemplateItem[],
  incomingOs: OsDefinition[] = []
): MergePlan {
  const existingByKey = new Map<string, TemplateItem>()
  for (const item of target.items) {
    const k = itemKey(item)
    if (!existingByKey.has(k)) existingByKey.set(k, item)
  }

  const knownTags = new Set(target.supportedOs.map(o => o.tag.toLowerCase()))
  const missingByTag = new Map<string, MissingOs>()

  // Incoming items are compared against each other as well as against the target: a
  // .reg file can legitimately set the same value twice, and importing both would
  // silently double it.
  const seenIncoming = new Map<string, TemplateItem>()

  const rows: MergeRow[] = incoming.map(item => {
    const key = itemKey(item)
    const earlier = seenIncoming.get(key) ?? null
    const existing = existingByKey.get(key) ?? earlier
    seenIncoming.set(key, item)

    let status: MergeStatus = 'new'
    if (existing) status = samePayload(item, existing) ? 'duplicate' : 'conflict'

    const notes: string[] = []
    if (earlier) notes.push('also in this import')
    if (item.payload.type === 'Registry' && item.payload.action === 'DeleteKeyRecursively') {
      notes.push('recursive delete')
    }

    // Collect OS tags this item references that the target does not define.
    for (const tag of Object.keys(item.os)) {
      if (knownTags.has(tag.toLowerCase()) || missingByTag.has(tag)) continue
      const carried = incomingOs.find(o => o.tag === tag)
      missingByTag.set(tag, {
        tag,
        // Without a carried definition, offer a stub built from the tag so the
        // mapping can be kept. It has no build numbers, so it matches no machine
        // until the user completes it in Manage OS. See applyMergePlan, which
        // forces execute off for stubs.
        definition: carried ?? { tag, name: tag, abbreviation: tag.slice(0, 6), isServerOs: false, buildStartsWith: [] },
        complete: !!carried,
        accepted: false
      })
    }

    return { key, status, item, existing, selected: status === 'new', notes }
  })

  // An item whose every OS tag will be pruned ends up running nowhere. The validator
  // does not flag this, so surface it as a row note.
  //
  // A tag survives if the target already knows it, or it can be added from the
  // preview. Every missing tag now offers a definition (a stub when none was
  // carried), so only an item with no tags at all can run nowhere.
  for (const row of rows) {
    const tags = Object.keys(row.item.os)
    const survivable = tags.some(t => knownTags.has(t.toLowerCase()) || missingByTag.has(t))
    if (!survivable) row.notes.push('will not run on any OS')
  }

  return {
    rows,
    missingOs: [...missingByTag.values()],
    counts: {
      new: rows.filter(r => r.status === 'new').length,
      duplicate: rows.filter(r => r.status === 'duplicate').length,
      conflict: rows.filter(r => r.status === 'conflict').length
    }
  }
}

/**
 * Resolve the user's choices into what should actually be applied.
 * Returns deep clones, so nothing handed to the store is aliased to the dialog.
 */
export function applyMergePlan(plan: MergePlan, target: TemplateDocument): MergeResult {
  const knownTags = new Set(target.supportedOs.map(o => o.tag.toLowerCase()))
  const accepted = plan.missingOs.filter(m => m.accepted)
  const acceptedTags = new Set(accepted.map(m => m.tag.toLowerCase()))
  // Tags added from a stub have no build numbers, so they cannot match a machine.
  // Force Execute off rather than leaving a mapping that looks enabled but is inert.
  const stubTags = new Set(accepted.filter(m => !m.complete).map(m => m.tag.toLowerCase()))

  const droppedOsTags = new Set<string>()
  const items: TemplateItem[] = []

  for (const row of plan.rows) {
    if (!row.selected) continue
    const clone: TemplateItem = JSON.parse(JSON.stringify(row.item))
    for (const tag of Object.keys(clone.os)) {
      const low = tag.toLowerCase()
      if (!knownTags.has(low) && !acceptedTags.has(low)) {
        delete clone.os[tag]
        droppedOsTags.add(tag)
        continue
      }
      if (stubTags.has(low)) clone.os[tag].execute = false
    }
    items.push(clone)
  }

  const osToAdd = accepted.map(m => JSON.parse(JSON.stringify(m.definition)) as OsDefinition)

  return { items, osToAdd, droppedOsTags: [...droppedOsTags] }
}
