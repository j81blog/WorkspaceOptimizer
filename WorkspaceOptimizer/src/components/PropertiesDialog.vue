<template>
  <BaseDialog :visible="visible" title="Template Properties" width="560px"
    @update:visible="onVisibleChange">

    <div class="pr-body">
      <p class="pr-lead">
        These describe the template itself. A marketplace catalog is generated from them,
        so Name, Description and Author are required before the XML can be downloaded.
      </p>

      <div class="field pr-field" data-tooltip="Stable identifier. Generated once and kept for the life of the template">
        <label class="field-lbl">Id (generated)</label>
        <div class="pr-id">
          <input class="field-inp mono" :value="draft.id" readonly />
          <button class="dlg-btn small" data-tooltip="Generate a new identifier, only for a template split off from another"
            @click="regenerateId">New</button>
        </div>
      </div>

      <div class="field pr-field" :class="{ 'pr-missing': !draft.name.trim() }"
        data-tooltip="Display name shown in the marketplace and used as the download filename">
        <label class="field-lbl">Name *</label>
        <input class="field-inp" v-model="draft.name" placeholder="e.g. VDI Baseline" />
      </div>

      <div class="field pr-field" :class="{ 'pr-missing': !draft.description.trim() }"
        data-tooltip="One or two sentences on what this template does">
        <label class="field-lbl">Description *</label>
        <textarea class="field-inp pr-textarea" v-model="draft.description" rows="2"
          placeholder="What does this template do?"></textarea>
      </div>

      <div class="field pr-field" :class="{ 'pr-missing': !draft.author.trim() }"
        data-tooltip="Who maintains this template">
        <label class="field-lbl">Author *</label>
        <input class="field-inp" v-model="draft.author" placeholder="e.g. Contoso IT" />
      </div>

      <div class="pr-row">
        <div class="field pr-field" data-tooltip="Groups the template in the marketplace list">
          <label class="field-lbl">Category</label>
          <input class="field-inp" v-model="draft.category" placeholder="e.g. Baseline" />
        </div>
        <div class="field pr-field" data-tooltip="Comma separated, used by marketplace search">
          <label class="field-lbl">Tags</label>
          <input class="field-inp" v-model="tagsText" placeholder="privacy, telemetry" />
        </div>
      </div>

      <div class="pr-versions">
        <span class="pr-vlabel">Version</span>
        <span class="mono">{{ draft.version || '(set on download)' }}</span>
        <span class="pr-vnote">re-stamped automatically when you download with unsaved changes</span>
      </div>
    </div>

    <template #footer>
      <span v-if="missing.length" class="pr-warn">
        {{ missing.join(', ') }} {{ missing.length === 1 ? 'is' : 'are' }} required
      </span>
      <button class="dlg-btn" data-tooltip="Discard changes and close" @click="onCancel">Cancel</button>
      <button class="dlg-btn primary" data-tooltip="Save these properties" @click="onSave">Save</button>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseDialog from './BaseDialog.vue'
import { documentStore } from '../store/document'
import type { TemplateMetadata } from '../core/types'

const props = defineProps<{ visible: boolean }>()
const emit = defineEmits<{ 'update:visible': [boolean] }>()

function blank(): TemplateMetadata {
  return { version: '', schemaVersion: '1', id: '', name: '', description: '', author: '', category: '', tags: [] }
}

const draft = ref<TemplateMetadata>(blank())
const tagsText = ref('')

/**
 * Edit a copy, commit on Save, the same draft pattern as OSDialog. An Id is generated
 * on open when the document has none, so a template always leaves here identifiable.
 */
watch(() => props.visible, (v) => {
  if (!v) return
  const meta = documentStore.document?.metadata
  draft.value = meta ? { ...meta, tags: [...meta.tags] } : blank()
  if (!draft.value.id) draft.value.id = crypto.randomUUID()
  tagsText.value = draft.value.tags.join(', ')
}, { immediate: true })

const missing = computed(() => {
  const out: string[] = []
  if (!draft.value.name.trim()) out.push('Name')
  if (!draft.value.description.trim()) out.push('Description')
  if (!draft.value.author.trim()) out.push('Author')
  return out
})

function regenerateId() {
  draft.value.id = crypto.randomUUID()
}

function onSave() {
  if (!documentStore.document) return
  documentStore.setMetadata({
    ...draft.value,
    name: draft.value.name.trim(),
    description: draft.value.description.trim(),
    author: draft.value.author.trim(),
    category: draft.value.category.trim(),
    tags: tagsText.value.split(',').map(t => t.trim()).filter(Boolean)
  })
  emit('update:visible', false)
}

function onCancel() {
  emit('update:visible', false)
}

// Backdrop click and Escape discard, like Cancel.
function onVisibleChange(v: boolean) {
  if (!v) onCancel()
}
</script>

<style scoped>
.pr-body { padding: 18px 20px; display: flex; flex-direction: column; gap: 12px; }
.pr-lead { font-size: 11px; color: var(--field-label); line-height: 1.6; }
.pr-field { border: 1px solid var(--field-border); border-radius: 6px; background: var(--field-bg); padding: 17px 10px 5px; position: relative; }
.pr-field:focus-within { border-color: var(--field-focus-bdr); }
.pr-missing { border-color: #b45309; }
.pr-textarea { resize: vertical; line-height: 1.5; }
.pr-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.pr-id { display: flex; gap: 8px; align-items: center; }
.pr-id .field-inp { flex: 1; opacity: 0.75; }
.pr-versions { display: flex; align-items: baseline; gap: 8px; font-size: 11px; color: var(--field-label); border-top: 1px solid var(--card-border); padding-top: 10px; }
.pr-vlabel { font-weight: 600; }
.pr-vnote { font-size: 10px; opacity: 0.8; }
.pr-warn { flex: 1; font-size: 11px; color: #f59e0b; font-weight: 600; }
</style>
