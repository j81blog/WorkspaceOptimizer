<template>
  <div class="mt-wrap">
    <div class="mt-toolbar">
      <label class="mt-check">
        <input type="checkbox" :checked="allSelected" :indeterminate.prop="someSelected" @change="selectAll(($event.target as HTMLInputElement).checked)" />
        <span>{{ selectedCount }} of {{ rows.length }} selected</span>
      </label>
      <div class="mt-chips">
        <button class="dlg-btn small" data-tooltip="Select only the items not already in the template" @click="selectNewOnly">New only</button>
        <button class="dlg-btn small" data-tooltip="Select every item" @click="selectAll(true)">All</button>
        <button class="dlg-btn small" data-tooltip="Deselect every item" @click="selectAll(false)">None</button>
      </div>
    </div>

    <!-- Bulk setters: a source usually gives every item the same category and order,
         chosen without knowing this template, so setting them all at once is the common
         case. Per-row edits below handle the exceptions. -->
    <div v-if="showOrder || showCategory" class="mt-bulk">
      <template v-if="showCategory">
        <span class="mt-bulk-lbl">Category</span>
        <input class="mt-inp mt-bulk-cat" v-model="bulkCategory" :placeholder="categoryHint"
          data-tooltip="Groups these items in the sidebar" @keydown.enter="applyBulkCategory" />
        <button class="dlg-btn small" :disabled="!bulkCategory.trim() || !selectedCount"
          data-tooltip="Apply this category to every selected item" @click="applyBulkCategory">Apply</button>
      </template>
      <template v-if="showOrder">
        <span class="mt-bulk-lbl" :class="{ 'mt-bulk-sep': showCategory }">Deploy order</span>
        <input class="mt-inp mt-bulk-inp" inputmode="numeric" v-model="bulkOrder" placeholder="100"
          data-tooltip="0–99999. Lower runs earlier" @keydown.enter="applyBulkOrder" />
        <button class="dlg-btn small" :disabled="!bulkValid || !selectedCount"
          data-tooltip="Apply this order to every selected item" @click="applyBulkOrder">Apply</button>
      </template>
      <span class="mt-bulk-note">applies to selected rows; or edit a row below</span>
    </div>

    <div class="mt-scroll">
      <table class="mt-table">
        <thead>
          <tr>
            <th class="c-tick"></th>
            <th class="c-status">Status</th>
            <th class="c-name">Name</th>
            <th v-if="showCategory" class="c-cat">Category</th>
            <th v-if="showOrder" class="c-order">Order</th>
            <th class="c-target">Target</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in rows" :key="row.item.id" :class="{ 'is-off': !row.selected }">
            <td class="c-tick">
              <input type="checkbox" :checked="row.selected" @change="row.selected = ($event.target as HTMLInputElement).checked" />
            </td>
            <td class="c-status">
              <span class="pill" :class="'pill--' + row.status">{{ row.status }}</span>
            </td>
            <td class="c-name">
              <input v-if="editableName" class="mt-inp" :value="row.item.name" @input="row.item.name = ($event.target as HTMLInputElement).value" />
              <span v-else class="mt-name">{{ row.item.name }}</span>
              <div v-if="row.notes.length" class="mt-notes">
                <span v-for="n in row.notes" :key="n" class="note" :class="{ 'note--danger': n === 'recursive delete' }">{{ n }}</span>
              </div>
            </td>
            <td v-if="showCategory" class="c-cat">
              <input class="mt-inp" :value="row.item.category" @input="row.item.category = ($event.target as HTMLInputElement).value" />
            </td>
            <td v-if="showOrder" class="c-order">
              <input class="mt-inp" inputmode="numeric" :value="row.item.order"
                data-tooltip="0–99999. Lower runs earlier"
                @input="row.item.order = clampOrder(($event.target as HTMLInputElement).value)" />
            </td>
            <td class="c-target">
              <div class="mono mt-target">{{ describe(row.item) }}</div>
              <div v-if="row.existing" class="mono mt-existing">existing: {{ summarizeValue(row.existing) }} → incoming: {{ summarizeValue(row.item) }}</div>
            </td>
          </tr>
          <tr v-if="!rows.length">
            <td :colspan="4 + (showCategory ? 1 : 0) + (showOrder ? 1 : 0)" class="mt-empty">Nothing to import.</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import type { MergeRow } from '../core/merge'
import type { TemplateItem } from '../core/types'

/**
 * Columns are opt-in per caller rather than one `editable` flag.
 *
 * A snippet author chose its names and categories deliberately, so those stay read-only
 * there; deploy order is the one field that depends on the destination template, so it is
 * editable in both callers. A .reg file supplies none of the three, so the wizard turns
 * everything on.
 */
const props = withDefaults(defineProps<{
  rows: MergeRow[]
  editableName?: boolean
  showCategory?: boolean
  showOrder?: boolean
}>(), {
  editableName: false,
  showCategory: false,
  showOrder: false
})

const bulkOrder = ref('')
const bulkCategory = ref('')
const bulkValid = computed(() => /^\d{1,5}$/.test(bulkOrder.value) && Number(bulkOrder.value) <= 99999)

/** Show the incoming category as the placeholder, so it is obvious what would change. */
const categoryHint = computed(() => {
  const cats = new Set(props.rows.map(r => r.item.category).filter(Boolean))
  return cats.size === 1 ? [...cats][0] : 'e.g. Visual Effects'
})

function applyBulkCategory() {
  const v = bulkCategory.value.trim()
  if (!v) return
  for (const r of props.rows) if (r.selected) r.item.category = v
}

/** Keep an edited order inside the range the validator accepts. */
function clampOrder(raw: string): number {
  const n = Number(raw.replace(/\D/g, ''))
  if (!Number.isFinite(n)) return 0
  return Math.min(n, 99999)
}

function applyBulkOrder() {
  if (!bulkValid.value) return
  const n = Number(bulkOrder.value)
  for (const r of props.rows) if (r.selected) r.item.order = n
}

const selectedCount = computed(() => props.rows.filter(r => r.selected).length)
const allSelected = computed(() => props.rows.length > 0 && selectedCount.value === props.rows.length)
const someSelected = computed(() => selectedCount.value > 0 && !allSelected.value)

function selectAll(on: boolean) {
  for (const r of props.rows) r.selected = on
}

function selectNewOnly() {
  for (const r of props.rows) r.selected = r.status === 'new'
}

/** One-line description of what the item touches. */
function describe(item: TemplateItem): string {
  const p = item.payload
  switch (p.type) {
    case 'Registry':      return `${p.hive}\\${p.path}${p.name ? '\\' + p.name : ''}`
    case 'Service':       return `service: ${p.name}`
    case 'ScheduledTask': return `task: ${p.path}${p.name}`
    case 'StoreApp':      return `app: ${p.name}`
    case 'FileFolder':    return `${p.itemType.toLowerCase()}: ${p.path}`
    case 'PowerShell':    return `${p.engine} script`
    default:              return item.typeRaw || 'unknown'
  }
}

/** The bit that actually differs between a conflicting pair. */
function summarizeValue(item: TemplateItem): string {
  const p = item.payload
  if (p.type === 'Registry') return p.action === 'SetValue' ? `${p.value} (${p.registryType})` : p.action
  if (p.type === 'Service' || p.type === 'ScheduledTask' || p.type === 'FileFolder') return p.action
  return '-'
}
</script>

<style scoped>
.mt-wrap { display: flex; flex-direction: column; min-height: 0; flex: 1; }
.mt-toolbar { display: flex; align-items: center; gap: 12px; padding: 10px 16px; border-bottom: 1px solid var(--card-border); flex-shrink: 0; }
.mt-check { display: flex; align-items: center; gap: 8px; font-size: 11px; color: var(--field-label); cursor: pointer; flex: 1; }
.mt-chips { display: flex; gap: 6px; }
/* min-width:0 on the row and a shrinkable note keep the Apply button inside the dialog:
   without it the nowrap children overflow horizontally instead of the text truncating. */
.mt-bulk { display: flex; align-items: center; gap: 8px; padding: 8px 16px; border-bottom: 1px solid var(--card-border); background: var(--sb-cat-bg); flex-shrink: 0; min-width: 0; }
.mt-bulk-lbl { font-size: 11px; color: var(--field-txt); white-space: nowrap; flex: 0 0 auto; }
/* Beats `.mt-inp { width: 100% }`, which is declared later for the row inputs and would
   otherwise stretch this one to the full bar and push Apply out of the dialog. */
.mt-bulk .mt-bulk-inp { width: 72px; flex: 0 0 auto; }
.mt-bulk .mt-bulk-cat { width: 150px; flex: 0 0 auto; }
.mt-bulk-sep { border-left: 1px solid var(--card-border); padding-left: 12px; margin-left: 4px; }
.mt-bulk .dlg-btn { flex: 0 0 auto; white-space: nowrap; }
.mt-bulk-note { font-size: 10px; color: var(--field-label); flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.mt-scroll { overflow-y: auto; flex: 1; min-height: 0; }
.mt-table { width: 100%; border-collapse: collapse; font-size: 11px; }
.mt-table thead th {
  position: sticky; top: 0; z-index: 1;
  background: var(--sb-cat-bg); color: var(--field-label);
  text-align: left; font-size: 9.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px;
  padding: 6px 10px; border-bottom: 1px solid var(--card-border);
}
.mt-table td { padding: 7px 10px; border-bottom: 1px solid var(--sb-border); vertical-align: top; }
.mt-table tr.is-off { opacity: 0.45; }
.c-tick { width: 32px; }
.c-status { width: 84px; }
.c-order { width: 70px; }
.c-cat { width: 130px; }
.mt-name { color: var(--item-name); font-weight: 600; }
.mt-inp {
  width: 100%; background: var(--field-bg); border: 1px solid var(--field-border); border-radius: 4px;
  color: var(--field-txt); font-family: 'Montserrat', sans-serif; font-size: 11px; padding: 3px 6px;
}
.mt-inp:focus { outline: none; border-color: var(--field-focus-bdr); }
.mt-target { color: var(--field-label); font-size: 10px; word-break: break-all; }
.mt-existing { color: #f59e0b; font-size: 10px; margin-top: 2px; }
.mt-notes { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 3px; }
.note { font-size: 9px; padding: 1px 5px; border-radius: 3px; background: var(--sb-input-bg); color: var(--field-label); }
.note--danger { background: var(--btn-danger-bg); color: var(--btn-danger-txt); }
.mt-empty { text-align: center; color: var(--field-label); padding: 24px; }
.pill { font-size: 9px; font-weight: 700; text-transform: uppercase; padding: 2px 7px; border-radius: 9px; }
.pill--new { background: #1d4e3a; color: #6fcf97; }
.pill--duplicate { background: var(--sb-input-bg); color: var(--field-label); }
.pill--conflict { background: #4a3a12; color: #f59e0b; }
[data-theme="light"] .pill--new { background: #dcfce7; color: #15803d; }
[data-theme="light"] .pill--conflict { background: #fef3c7; color: #b45309; }
</style>
