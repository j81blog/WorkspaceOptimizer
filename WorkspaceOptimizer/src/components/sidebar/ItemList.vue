<template>
  <div class="sb-search">
    <div class="search-row">
      <input v-model="uiStore.filters.search" class="sb-input" placeholder="Search items…" />
      <button v-if="uiStore.filters.search" class="x-btn" data-tooltip="Clear search filter" @click="uiStore.setFilter('search','')">×</button>
    </div>
    <div class="filters-grid">
      <div class="filter-group">
        <span class="filter-lbl">Category</span>
        <select class="sb-select" :value="uiStore.filters.category"
          @change="uiStore.setFilter('category', ($event.target as HTMLSelectElement).value)">
          <option value="">All</option>
          <option v-for="c in categories" :key="c" :value="c">{{ c }}</option>
        </select>
      </div>
      <div class="filter-group">
        <span class="filter-lbl">Type</span>
        <select class="sb-select" :value="uiStore.filters.type"
          @change="uiStore.setFilter('type', ($event.target as HTMLSelectElement).value)">
          <option value="">All</option>
          <option v-for="t in TYPES" :key="t" :value="t">{{ t }}</option>
        </select>
      </div>
      <div class="filter-group">
        <span class="filter-lbl">OS</span>
        <select class="sb-select" :value="uiStore.filters.os"
          @change="uiStore.setFilter('os', ($event.target as HTMLSelectElement).value)">
          <option value="">All</option>
          <option v-for="o in supportedOs" :key="o.tag" :value="o.tag">{{ o.name }}</option>
        </select>
      </div>
    </div>
  </div>

  <div class="sb-actions">
    <div class="action-row">
      <button class="sb-btn add" data-tooltip="Add a new item" @click="onAdd">+ New</button>
      <button class="sb-btn dup" :disabled="!uiStore.selectedId" data-tooltip="Duplicate the selected item" @click="onDuplicate">Duplicate</button>
      <button class="sb-btn del" :disabled="!uiStore.selectedId" data-tooltip="Delete the selected item" @click="onDelete">Delete</button>
    </div>
    <div class="action-row">
      <button class="sb-btn" :class="{ active: uiStore.viewMode==='category' }" data-tooltip="Group and sort items by category" @click="uiStore.setViewMode('category')">Category</button>
      <button class="sb-btn" :class="{ active: uiStore.viewMode==='order' }" data-tooltip="Sort items by deploy order number" @click="uiStore.setViewMode('order')">Deploy Order</button>
      <button v-if="uiStore.viewMode==='category'" class="sb-btn" data-tooltip="Toggle alphabetical sort direction" @click="uiStore.toggleSort">
        {{ uiStore.sortDir === 'asc' ? 'A→Z' : 'Z→A' }}
      </button>
    </div>
  </div>

  <div class="item-list">
    <template v-if="uiStore.viewMode === 'category'">
      <template v-for="group in grouped" :key="group.category">
        <div class="cat-hdr" @click="toggleCat(group.category)" style="cursor:pointer">
          <span><span class="cat-arrow">{{ collapsedCats.has(group.category) ? '▶' : '▼' }}</span>{{ group.category }}</span>
          <span class="cat-count">{{ group.items.length }}</span>
        </div>
        <template v-if="!collapsedCats.has(group.category)">
          <ItemRow v-for="item in group.items" :key="item.id"
            :item="item" :is-active="uiStore.selectedId === item.id" :view-mode="uiStore.viewMode"
            @select="uiStore.select(item.id)" />
        </template>
      </template>
    </template>
    <template v-else>
      <ItemRow v-for="item in filtered" :key="item.id"
        :item="item" :is-active="uiStore.selectedId === item.id" :view-mode="uiStore.viewMode"
        @select="uiStore.select(item.id)" />
    </template>
  </div>

  <div class="sb-footer">
    <span class="sf-dot"></span>
    <span class="sf-valid">{{ filtered.length }} item{{ filtered.length !== 1 ? 's' : '' }}</span>
    <span v-if="documentStore.validationResult.errors.length" style="color:#f87171">
      {{ documentStore.validationResult.errors.length }} error{{ documentStore.validationResult.errors.length !== 1 ? 's' : '' }}
    </span>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { documentStore } from '../../store/document'
import { uiStore } from '../../store/ui'
import type { TemplateItem } from '../../core/types'
import ItemRow from './ItemRow.vue'

const TYPES = ['Registry','Service','ScheduledTask','StoreApp','PowerShell','FileFolder']
const collapsedCats = ref(new Set<string>())
function toggleCat(cat: string) { if (collapsedCats.value.has(cat)) { collapsedCats.value.delete(cat) } else { collapsedCats.value.add(cat) }; collapsedCats.value = new Set(collapsedCats.value) }
const all = computed(() => documentStore.document?.items ?? [])
const supportedOs = computed(() => documentStore.document?.supportedOs ?? [])
const categories = computed(() => [...new Set(all.value.map(i => i.category).filter(Boolean))].sort())

const filtered = computed(() => {
  let items = all.value
  const { search, category, type, os } = uiStore.filters
  if (search) {
    const q = search.toLowerCase()
    items = items.filter(i => {
      if (i.name.toLowerCase().includes(q)) return true
      if (i.category.toLowerCase().includes(q)) return true
      if (i.description.toLowerCase().includes(q)) return true
      const p = i.payload as Record<string, unknown>
      if (typeof p.name === 'string' && p.name.toLowerCase().includes(q)) return true
      if (typeof p.path === 'string' && p.path.toLowerCase().includes(q)) return true
      return false
    })
  }
  if (category) items = items.filter(i => i.category === category)
  if (type) items = items.filter(i => i.type === type)
  if (os) items = items.filter(i => os in i.os)
  return [...items].sort((a, b) =>
    uiStore.viewMode === 'order'
      ? (a.order - b.order) || a.name.localeCompare(b.name)
      : a.name.toLowerCase().localeCompare(b.name.toLowerCase()) * (uiStore.sortDir === 'asc' ? 1 : -1)
  )
})

const grouped = computed(() => {
  const map = new Map<string, TemplateItem[]>()
  for (const item of filtered.value) {
    const cat = item.category || '(none)'
    if (!map.has(cat)) map.set(cat, [])
    map.get(cat)!.push(item)
  }
  return [...map.entries()].sort(([a],[b]) => a.localeCompare(b)).map(([category, items]) => ({ category, items }))
})

function onAdd() {
  const item: TemplateItem = { id: crypto.randomUUID(), name: 'New Item', description: '', type: 'Service', typeRaw: 'Service', category: 'General', order: 100, os: {}, payload: { type: 'Service', name: '', action: 'Disabled' } }
  documentStore.addItem(item)
  uiStore.select(item.id)
}

function onDuplicate() {
  const src = all.value.find(i => i.id === uiStore.selectedId)
  if (!src) return
  const copy: TemplateItem = { ...src, id: crypto.randomUUID(), name: src.name + ' (copy)', os: { ...src.os }, payload: { ...src.payload } as any }
  documentStore.addItem(copy)
  uiStore.select(copy.id)
}

function onDelete() {
  if (!uiStore.selectedId) return
  const item = all.value.find(i => i.id === uiStore.selectedId)
  if (!item || !confirm(`Delete "${item.name}"?`)) return
  const idx = all.value.findIndex(i => i.id === uiStore.selectedId)
  documentStore.deleteItem(uiStore.selectedId)
  const remaining = documentStore.document?.items ?? []
  uiStore.select(remaining[Math.min(idx, remaining.length - 1)]?.id ?? null)
}
</script>

<style scoped>
.sb-search { padding: 14px 16px 12px; border-bottom: 1px solid var(--sb-border); flex-shrink: 0; }
.search-row { display: flex; gap: 8px; margin-bottom: 10px; }
.sb-input { flex: 1; height: 36px; background: var(--sb-input-bg); border: 1px solid var(--sb-input-bdr); border-radius: 6px; color: var(--sb-input-txt); font-size: 12px; font-family: 'Montserrat', sans-serif; padding: 0 12px; }
.sb-input:focus { outline: none; border-color: var(--item-bar); }
.x-btn { width: 36px; height: 36px; background: var(--sb-input-bg); border: 1px solid var(--sb-input-bdr); border-radius: 6px; color: var(--sb-placeholder); font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; }
.filters-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; }
.filter-group { display: flex; flex-direction: column; gap: 3px; }
.filter-lbl { font-size: 9px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; color: var(--sb-placeholder); }
.sb-select { height: 30px; background: var(--sb-input-bg); border: 1px solid var(--sb-input-bdr); border-radius: 5px; color: var(--sb-select-txt); font-size: 10px; font-family: 'Montserrat', sans-serif; padding: 0 6px; width: 100%; }
.sb-actions { padding: 10px 16px; border-bottom: 1px solid var(--sb-border); display: flex; flex-direction: column; gap: 7px; flex-shrink: 0; }
.action-row { display: flex; gap: 6px; }
.sb-btn { flex: 1; height: 32px; border-radius: 6px; border: 1px solid var(--sb-btn-bdr); background: var(--sb-btn-bg); color: var(--sb-btn-txt); font-size: 11px; font-family: 'Montserrat', sans-serif; font-weight: 600; cursor: pointer; }
.sb-btn:hover { background: var(--sb-btn-hover-bg); }
.sb-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.sb-btn.active { border-color: var(--item-bar); color: var(--item-bar); }
[data-theme="dark"] .sb-btn.add { background: #1d4e3a; border-color: #2d6a4f; color: #6fcf97; }
[data-theme="dark"] .sb-btn.del { background: #4a1a1a; border-color: #6b2828; color: #ff8a8a; }
[data-theme="dark"] .sb-btn.dup { background: #2a2050; border-color: #3d3070; color: #b39ddb; }
[data-theme="light"] .sb-btn.add { background: #eff6ff; border-color: #bfdbfe; color: #2563eb; }
[data-theme="light"] .sb-btn.del { background: #fff1f2; border-color: #fda4af; color: #dc2626; }
[data-theme="light"] .sb-btn.dup { background: #faf5ff; border-color: #d8b4fe; color: #7c3aed; }
.item-list { flex: 1; overflow-y: auto; }
.cat-hdr { display: flex; justify-content: space-between; align-items: center; padding: 6px 16px; font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; color: var(--sb-cat-txt); background: var(--sb-cat-bg); border-bottom: 1px solid var(--sb-border); }
.cat-count { background: var(--sb-input-bg); padding: 1px 7px; border-radius: 8px; font-size: 9px; color: var(--sb-placeholder); }
.cat-arrow { margin-right: 5px; font-size: 8px; }
.sb-footer { padding: 9px 16px; border-top: 1px solid var(--sb-border); display: flex; align-items: center; gap: 8px; font-size: 10px; flex-shrink: 0; }
.sf-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--sb-footer-dot); }
.sf-valid { color: var(--sb-footer-valid); flex: 1; }
</style>
