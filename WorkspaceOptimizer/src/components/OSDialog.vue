<template>
  <BaseDialog :visible="visible" title="Manage Supported OS" width="780px" :scroll-body="false"
    @update:visible="onVisibleChange">

    <div class="os-body">
      <!-- Left: OS list -->
      <div class="dlg-list">
        <div class="dlg-list-actions">
          <button class="dlg-btn primary" data-tooltip="Add a new operating system" @click="onAddOs">Add OS</button>
          <button class="dlg-btn danger" :disabled="!selectedTag" data-tooltip="Delete the selected operating system" @click="onDeleteOs">Delete OS</button>
        </div>
        <div class="os-list-items">
          <div v-for="os in draft" :key="os.tag"
            class="os-list-item" :class="{ active: selectedTag === os.tag }"
            @click="selectedTag = os.tag">
            <div class="osli-name">{{ os.name }}</div>
            <div class="osli-tag">{{ os.tag }}</div>
          </div>
        </div>
      </div>

      <!-- Right: Detail form -->
      <div class="dlg-detail" v-if="selected">
        <p class="detail-heading">OS Details</p>

        <div class="field dlg-field" data-tooltip="Unique identifier used in XML output and item OS mappings">
          <label class="field-lbl">Tag *</label>
          <input class="field-inp" :value="selected.tag" @input="updateSelected('tag', ($event.target as HTMLInputElement).value)" />
        </div>
        <div class="field dlg-field" data-tooltip="Display name shown in the OS list and PDF reports">
          <label class="field-lbl">Name *</label>
          <input class="field-inp" :value="selected.name" @input="updateSelected('name', ($event.target as HTMLInputElement).value)" />
        </div>
        <div class="field dlg-field" data-tooltip="Short label shown in the OS mapping table. Auto-derived from the name if left empty">
          <label class="field-lbl">Abbreviation (auto-derived if empty)</label>
          <input class="field-inp" :value="selected.abbreviation" @input="updateSelected('abbreviation', ($event.target as HTMLInputElement).value)" :placeholder="derivedAbbrev" />
        </div>

        <label class="server-os-label" data-tooltip="Mark this as a server edition operating system">
          <input type="checkbox" :checked="selected.isServerOs" @change="updateSelected('isServerOs', ($event.target as HTMLInputElement).checked)" />
          Server OS
        </label>

        <div class="build-section">
          <div class="build-hdr">
            <span class="build-title">Build</span>
            <div>
              <button class="dlg-btn small" data-tooltip="Add a build number entry" @click="addBuild">Add</button>
              <button class="dlg-btn small danger" :disabled="selectedBuildIdx === null" data-tooltip="Remove the selected build entry" @click="removeBuild">Remove</button>
            </div>
          </div>
          <div class="build-list">
            <div class="build-col-hdr" data-tooltip="Windows build number, or the starting digits of the build number (e.g. 19041 or 220)">BuildStartsWith</div>
            <div v-for="(b, i) in selected.buildStartsWith" :key="i"
              class="build-row" :class="{ active: selectedBuildIdx === i }"
              @click="selectedBuildIdx = i">
              <input class="build-inp" inputmode="numeric" data-tooltip="Windows build number, or the starting digits of the build number (e.g. 19041 or 220)" :value="b" @input="updateBuild(i, ($event.target as HTMLInputElement).value)" @click.stop />
            </div>
          </div>
        </div>
      </div>
      <div v-else class="dlg-detail dlg-empty">Select an OS entry or add a new one.</div>
    </div>

    <template #footer>
      <button class="dlg-btn" data-tooltip="Discard changes and close" @click="onCancel">Cancel</button>
      <button class="dlg-btn primary" data-tooltip="Save all operating system changes" @click="onSave">Save</button>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseDialog from './BaseDialog.vue'
import { documentStore } from '../store/document'
import type { OsDefinition } from '../core/types'

const props = defineProps<{ visible: boolean }>()
const emit = defineEmits<{ 'update:visible': [boolean]; saved: [] }>()

const draft = ref<OsDefinition[]>([])
const selectedTag = ref<string | null>(null)
const selectedBuildIdx = ref<number | null>(null)

// Deep-copy current OS list into draft when dialog opens
watch(() => props.visible, (v) => {
  if (v) {
    draft.value = JSON.parse(JSON.stringify(documentStore.document?.supportedOs ?? []))
    selectedTag.value = draft.value[0]?.tag ?? null
  }
})

const selected = computed(() => draft.value.find(o => o.tag === selectedTag.value) ?? null)

const derivedAbbrev = computed(() => {
  if (!selected.value?.name) return ''
  return selected.value.name
    .split(' ')
    .map((w, i, arr) => /^\d/.test(w) ? w : (i === 0 || i === arr.length - 1 ? w[0] : ''))
    .join('')
    .replace(/[^A-Za-z0-9]/g, '')
})

function updateSelected(field: keyof OsDefinition, value: unknown) {
  if (!selected.value) return
  ;(selected.value as any)[field] = value
  if (field === 'tag') selectedTag.value = value as string
}

function addBuild() {
  selected.value?.buildStartsWith.push('')
  selectedBuildIdx.value = (selected.value?.buildStartsWith.length ?? 1) - 1
}

function removeBuild() {
  if (selectedBuildIdx.value === null || !selected.value) return
  selected.value.buildStartsWith.splice(selectedBuildIdx.value, 1)
  selectedBuildIdx.value = null
}

function updateBuild(i: number, value: string) {
  if (!selected.value) return
  const numeric = value.replace(/\D/g, '')
  selected.value.buildStartsWith[i] = numeric
  const el = document.activeElement as HTMLInputElement | null
  if (el && el.value !== numeric) el.value = numeric
}

function onAddOs() {
  const newOs: OsDefinition = { tag: `NewOS${Date.now()}`, name: 'New OS', abbreviation: '', isServerOs: false, buildStartsWith: [] }
  draft.value.push(newOs)
  selectedTag.value = newOs.tag
}

function onDeleteOs() {
  if (!selectedTag.value) return
  const tag = selectedTag.value
  const inUse = documentStore.document?.items.some(i => tag in i.os)
  if (inUse && !confirm(`"${tag}" is used by items. Delete anyway?`)) return
  draft.value = draft.value.filter(o => o.tag !== tag)
  selectedTag.value = draft.value[0]?.tag ?? null
}

function deriveAbbrev(name: string): string {
  return name
    .split(' ')
    .map((w, i, arr) => /^\d/.test(w) ? w : (i === 0 || i === arr.length - 1 ? w[0] : ''))
    .join('')
    .replace(/[^A-Za-z0-9]/g, '')
}

function onSave() {
  // Derive abbreviations where empty, computed per-item
  const finalList = draft.value.map(os => ({
    ...os,
    abbreviation: os.abbreviation || deriveAbbrev(os.name)
  }))
  documentStore.setOsDefinitions(finalList)
  emit('update:visible', false)
  emit('saved')
}

function onCancel() {
  emit('update:visible', false)
}

/** Backdrop click and Escape both route here, so they discard like Cancel. */
function onVisibleChange(v: boolean) {
  if (!v) onCancel()
}
</script>

<style scoped>
/* Backdrop, header, footer and .dlg-btn come from BaseDialog and style.css. */
.os-body { display: flex; flex: 1; overflow: visible; min-height: 0; }
.dlg-list { width: 260px; flex-shrink: 0; border-right: 1px solid var(--card-border); display: flex; flex-direction: column; }
.dlg-list-actions { display: flex; gap: 8px; padding: 12px; border-bottom: 1px solid var(--card-border); }
.os-list-items { flex: 1; overflow-y: auto; }
.os-list-item { padding: 10px 14px; cursor: pointer; border-bottom: 1px solid var(--sb-border); }
.os-list-item:hover { background: var(--item-hover); }
.os-list-item.active { background: var(--item-active); border-left: 2px solid var(--item-bar); }
.osli-name { font-size: 12px; font-weight: 600; color: var(--item-name); }
.osli-tag { font-size: 10px; color: var(--field-label); margin-top: 2px; }
.dlg-detail { flex: 1; padding: 16px 20px; overflow: visible; display: flex; flex-direction: column; gap: 10px; }
.dlg-empty { align-items: center; justify-content: center; color: var(--field-label); font-size: 12px; }
.detail-heading { font-size: 13px; font-weight: 700; color: var(--bc-name); margin-bottom: 4px; }
.dlg-field { border: 1px solid var(--field-border); border-radius: 6px; background: var(--field-bg); padding: 17px 10px 5px; position: relative; }
.dlg-field:focus-within { border-color: var(--field-focus-bdr); }
.server-os-label { display: flex; align-items: center; gap: 8px; font-size: 12px; color: var(--field-txt); cursor: pointer; }
.build-section { border: 1px solid var(--card-border); border-radius: 6px; overflow: hidden; }
.build-hdr { display: flex; justify-content: space-between; align-items: center; padding: 8px 12px; background: var(--item-bar); }
.build-title { font-size: 11px; font-weight: 700; color: #fff; }
.build-list { padding: 0; }
.build-col-hdr { padding: 6px 12px; font-size: 10px; font-weight: 700; text-transform: uppercase; color: var(--field-label); background: var(--sb-cat-bg); }
.build-row { display: flex; border-bottom: 1px solid var(--sb-border); }
.build-row.active { background: var(--item-active); }
.build-inp { flex: 1; background: transparent; border: none; outline: none; padding: 7px 12px; font-size: 12px; font-family: 'Montserrat', sans-serif; color: var(--field-txt); }
</style>
