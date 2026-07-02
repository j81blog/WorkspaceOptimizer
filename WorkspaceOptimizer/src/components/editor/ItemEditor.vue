<template>
  <div v-if="!item" class="editor-empty">
    <p>
      Click <strong>New from Default</strong> in the toolbar to start with a default template.
    </p>
    <p>
      Click <strong>Open Template</strong> in the toolbar to open and edit your own template.
    </p>
    <p>
      Click <strong>Download Script</strong> in the toolbar to get the PowerShell deployment script anytime.
    </p>
    <p class="ee-note">Once a template is loaded you can also:</p>
    <p class="ee-disabled">
      <strong>Download XML</strong> to save your configured template as an XML file.
    </p>
  </div>

  <div v-else class="editor-layout">
    <!-- Breadcrumb -->
    <div class="bc-bar">
      <span class="bc-cat">{{ item.category || '—' }}</span>
      <span class="bc-sep">›</span>
      <span class="bc-name">{{ item.name || '(unnamed)' }}</span>
      <span class="bc-badge" :style="{ color: accentColor, borderColor: accentColor, background: accentColor + '1f' }">{{ item.type }}</span>
    </div>

    <!-- Scrollable editor column -->
    <div class="editor-scroll">
      <!-- Two-column: left = General+Payload, right = OS Mapping (starts at same height) -->
      <div class="editor-cols">
        <div class="editor-main">
          <!-- General card -->
          <div class="card" style="margin-bottom:12px">
            <div class="card-hdr">
              <div class="c-accent" style="background:var(--item-bar)"></div>
              <span class="c-label">General</span>
            </div>
            <div class="card-body">
              <!-- Line 1: Name + Order (75% / 25%) -->
              <div class="field-grid">
                <div class="col-9">
                  <div class="field">
                    <label class="field-lbl">Name *</label>
                    <input class="field-inp" :value="item.name" @input="update('name', ($event.target as HTMLInputElement).value)" />
                  </div>
                </div>
                <div class="col-3">
                  <div class="field">
                    <label class="field-lbl">Order</label>
                    <input class="field-inp" type="number" min="0" max="99999" :value="item.order"
                      @input="update('order', parseInt(($event.target as HTMLInputElement).value) || 100)" />
                  </div>
                </div>
              </div>
              <!-- Line 2: Description (full width) -->
              <div class="field-grid">
                <div class="col-12">
                  <div class="field">
                    <label class="field-lbl">Description</label>
                    <textarea ref="descRef" class="field-inp field-ta" rows="1" :value="item.description" @input="onDescInput" />
                  </div>
                </div>
              </div>
              <!-- Line 3: Type + Category -->
              <div class="field-grid">
                <div class="col-6">
                  <div class="field">
                    <label class="field-lbl">Type *</label>
                    <select class="field-inp" :value="item.type" @change="onTypeChange(($event.target as HTMLSelectElement).value as ItemType)">
                      <option v-for="t in ITEM_TYPES" :key="t" :value="t">{{ t }}</option>
                    </select>
                  </div>
                </div>
                <div class="col-6">
                  <div class="field">
                    <label class="field-lbl">Category *</label>
                    <div class="cat-row">
                      <select class="field-inp" :value="item.category" @change="update('category', ($event.target as HTMLSelectElement).value)">
                        <option v-if="!item.category" value="" disabled>— select category —</option>
                        <option v-for="c in categories" :key="c" :value="c">{{ c }}</option>
                      </select>
                      <button class="cat-add-btn" title="Add new category" @click="openCatDialog">+</button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <!-- Payload card -->
          <component :is="payloadComponent" :item="item" @update="onPayloadUpdate" />
        </div>
        <div class="editor-side">
          <OSMappingTable :item="item" />
        </div>
      </div>

      <!-- Validation issues for this item -->
      <div v-if="itemErrors.length" class="item-issues">
        <div v-for="issue in itemErrors" :key="issue.code + issue.path" class="issue-row" :class="issue.severity.toLowerCase()">
          <span class="issue-icon">{{ issue.severity === 'Error' ? '✕' : '⚠' }}</span>
          <span class="issue-msg">{{ issue.message }}</span>
        </div>
      </div>
    </div>
    <!-- Add Category dialog -->
    <div v-if="showCatDialog" class="dlg-overlay" @click.self="showCatDialog = false">
      <div class="dlg">
        <div class="dlg-title">Add Category</div>
        <input ref="catInput" class="dlg-inp" v-model="newCatName" placeholder="Category name"
          @keydown.enter="confirmAddCat" @keydown.escape="showCatDialog = false" />
        <div v-if="catError" class="dlg-error">{{ catError }}</div>
        <div class="dlg-actions">
          <button class="dlg-btn secondary" data-tooltip="Cancel and close" @click="showCatDialog = false">Cancel</button>
          <button class="dlg-btn primary" data-tooltip="Add the new category" @click="confirmAddCat">Add</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, defineAsyncComponent, ref, nextTick, watch } from 'vue'
import { documentStore } from '../../store/document'
import { uiStore } from '../../store/ui'
import type { TemplateItem, ItemType, ItemPayload } from '../../core/types'
import OSMappingTable from '../OSMappingTable.vue'

const ITEM_TYPES: ItemType[] = ['Registry','Service','ScheduledTask','StoreApp','PowerShell','FileFolder']

const accentMap: Record<string, string> = {
  Registry: '#fb923c', Service: '#38bdf8', ScheduledTask: '#a78bfa',
  StoreApp: '#f472b6', PowerShell: '#4ade80', FileFolder: '#2dd4bf', Unknown: '#94a3b8'
}

const item = computed(() => documentStore.document?.items.find(i => i.id === uiStore.selectedId) ?? null)
const categories = computed(() => [...new Set(documentStore.document?.items.map(i => i.category).filter(Boolean))].sort())
const accentColor = computed(() => accentMap[item.value?.type ?? 'Unknown'])
const itemErrors = computed(() => documentStore.validationResult.errors.filter(e => e.itemId === item.value?.id))

const payloadComponents: Record<string, ReturnType<typeof defineAsyncComponent>> = {
  Registry: defineAsyncComponent(() => import('./payload/PayloadRegistry.vue')),
  Service: defineAsyncComponent(() => import('./payload/PayloadService.vue')),
  ScheduledTask: defineAsyncComponent(() => import('./payload/PayloadScheduledTask.vue')),
  StoreApp: defineAsyncComponent(() => import('./payload/PayloadStoreApp.vue')),
  PowerShell: defineAsyncComponent(() => import('./payload/PayloadPowerShell.vue')),
  FileFolder: defineAsyncComponent(() => import('./payload/PayloadFileFolder.vue')),
}

const payloadComponent = computed(() => payloadComponents[item.value?.type ?? ''] ?? null)

function update(field: keyof TemplateItem, value: unknown) {
  if (!item.value) return
  documentStore.updateItem(item.value.id, { [field]: value })
}

function onTypeChange(newType: ItemType) {
  if (!item.value) return
  const defaultPayloads: Record<ItemType, ItemPayload> = {
    Registry: { type: 'Registry', hive: 'HKLM', path: '', name: '', action: 'SetValue', value: '', registryType: 'DWord' },
    Service: { type: 'Service', name: '', action: 'Disabled' },
    ScheduledTask: { type: 'ScheduledTask', name: '', path: '', action: 'Disabled' },
    StoreApp: { type: 'StoreApp', name: '' },
    PowerShell: { type: 'PowerShell', engine: 'powershell', script: '' },
    FileFolder: { type: 'FileFolder', path: '', action: 'Remove', itemType: 'File', newName: '' },
    Unknown: { type: 'Unknown' }
  }
  documentStore.updateItem(item.value.id, { type: newType, typeRaw: newType, payload: defaultPayloads[newType] })
}

const descRef = ref<HTMLTextAreaElement | null>(null)

function onDescInput(e: Event) {
  const el = e.target as HTMLTextAreaElement
  update('description', el.value)
  el.style.height = 'auto'
  el.style.height = el.scrollHeight + 'px'
}

watch(() => item.value?.id, () => {
  nextTick(() => {
    if (descRef.value) {
      descRef.value.style.height = 'auto'
      descRef.value.style.height = descRef.value.scrollHeight + 'px'
    }
  })
})

const showCatDialog = ref(false)
const newCatName = ref('')
const catError = ref('')
const catInput = ref<HTMLInputElement | null>(null)

function openCatDialog() {
  newCatName.value = ''
  catError.value = ''
  showCatDialog.value = true
  nextTick(() => catInput.value?.focus())
}

function confirmAddCat() {
  const name = newCatName.value.trim()
  if (!name) { catError.value = 'Name is required.'; return }
  if (categories.value.includes(name)) { catError.value = 'Category already exists.'; return }
  if (!item.value) return
  documentStore.updateItem(item.value.id, { category: name })
  showCatDialog.value = false
}

function onPayloadUpdate(patch: Partial<ItemPayload>) {
  if (!item.value) return
  documentStore.updateItem(item.value.id, { payload: { ...item.value.payload, ...patch } as ItemPayload })
}
</script>

<style scoped>
.editor-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; flex: 1; color: var(--bc-name); font-size: 18px; gap: 14px; }
.editor-empty p { margin: 0; text-align: center; display: flex; align-items: center; justify-content: center; gap: 8px; flex-wrap: wrap; line-height: 1.5; }
.ee-icon { display: inline-flex; align-items: center; }
.ee-icon svg { width: 1.1em; height: 1.1em; fill: none; stroke: var(--item-bar); stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; vertical-align: middle; }
.ee-icon svg.icon-filled { fill: var(--item-bar); stroke: none; }
.ee-disabled .ee-icon svg.icon-filled { fill: var(--field-label); }
.ee-note { color: var(--field-label); margin-top: 6px; opacity: 0.85; }
.ee-disabled { opacity: 0.45; }
.ee-disabled .ee-icon svg { stroke: var(--field-label); }
.editor-layout { display: flex; flex-direction: column; flex: 1; overflow: hidden; }
.bc-bar { display: flex; align-items: center; gap: 8px; padding: 9px 16px; background: var(--bc-bg); border-bottom: 1px solid var(--bc-border); flex-shrink: 0; }
.bc-cat { font-size: 11px; color: var(--bc-cat); font-weight: 500; }
.bc-sep { color: var(--bc-cat); }
.bc-name { font-size: 12px; font-weight: 700; color: var(--bc-name); flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.bc-badge { font-size: 10px; padding: 2px 9px; border-radius: 4px; background: var(--bc-badge-bg); color: var(--bc-badge-txt); font-weight: 700; border: 1px solid var(--bc-badge-bdr); }
.editor-scroll { flex: 1; overflow-y: auto; padding: 14px 16px; display: flex; flex-direction: column; gap: 12px; }
.editor-cols { display: flex; gap: 12px; align-items: flex-start; }
.editor-main { flex: 1; min-width: 0; }
.editor-side { width: 380px; flex-shrink: 0; }
.item-issues { display: flex; flex-direction: column; gap: 4px; }
.issue-row { display: flex; align-items: flex-start; gap: 8px; padding: 8px 12px; border-radius: 6px; font-size: 11px; }
.issue-row.error { background: rgba(248,113,113,0.08); border: 1px solid rgba(248,113,113,0.2); color: #f87171; }
.issue-row.warning { background: rgba(251,191,36,0.08); border: 1px solid rgba(251,191,36,0.2); color: #fbbf24; }
.issue-icon { font-size: 10px; flex-shrink: 0; margin-top: 1px; }

.field-ta { resize: none; overflow-y: auto; line-height: 1.5; max-height: calc(5 * 1.5em + 14px); }
.cat-row { display: flex; align-items: center; gap: 4px; }
.cat-row .field-inp { flex: 1; min-width: 0; }
.cat-add-btn { flex-shrink: 0; width: 22px; align-self: stretch; padding: 0; border: 1px solid var(--field-border); border-radius: 4px; background: var(--field-bg); color: var(--field-txt); font-size: 16px; line-height: 1; cursor: pointer; display: flex; align-items: center; justify-content: center; }
.cat-add-btn:hover { background: var(--bc-badge-bg); }

.dlg-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 1000; }
.dlg { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 8px; padding: 20px; min-width: 280px; display: flex; flex-direction: column; gap: 12px; box-shadow: 0 8px 32px rgba(0,0,0,0.3); }
.dlg-title { font-size: 13px; font-weight: 700; color: var(--bc-name); }
.dlg-inp { background: var(--field-bg); border: 1px solid var(--field-border); border-radius: 5px; padding: 7px 10px; font-size: 12px; font-family: inherit; color: var(--field-txt); outline: none; width: 100%; }
.dlg-inp:focus { border-color: var(--accent, #3b82f6); }
.dlg-error { font-size: 11px; color: #f87171; }
.dlg-actions { display: flex; justify-content: flex-end; gap: 8px; }
.dlg-btn { padding: 6px 14px; border-radius: 5px; font-size: 12px; font-family: inherit; cursor: pointer; border: 1px solid transparent; }
.dlg-btn.secondary { background: transparent; border-color: var(--field-border); color: var(--field-txt); }
.dlg-btn.primary { background: #3b82f6; color: #fff; border-color: #3b82f6; }
.dlg-btn.primary:hover { background: #2563eb; }
</style>
