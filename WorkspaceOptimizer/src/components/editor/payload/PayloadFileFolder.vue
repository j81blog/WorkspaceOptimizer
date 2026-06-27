<template>
  <div class="card">
    <div class="card-hdr">
      <div class="c-accent" style="background:#0ea5e9"></div>
      <span class="c-label">File / Folder</span>
    </div>
    <div class="card-body">
      <div class="field-grid">
        <div class="col-6">
          <div class="field">
            <label class="field-lbl">Item Type *</label>
            <select class="field-inp" :value="p.itemType" @change="emit('update', { itemType: ($event.target as HTMLSelectElement).value })">
              <option>File</option><option>Folder</option>
            </select>
          </div>
        </div>
        <div class="col-6">
          <div class="field">
            <label class="field-lbl">Action *</label>
            <select class="field-inp" :value="p.action" @change="emit('update', { action: ($event.target as HTMLSelectElement).value })">
              <option>Remove</option><option>Rename</option>
            </select>
          </div>
        </div>
      </div>
      <div class="field-grid">
        <div class="col-12">
          <div class="field">
            <label class="field-lbl">Path *</label>
            <input class="field-inp mono" :value="p.path" @input="emit('update', { path: ($event.target as HTMLInputElement).value })" />
          </div>
        </div>
      </div>
      <div v-if="p.action === 'Rename'" class="field-grid">
        <div class="col-12">
          <div class="field">
            <label class="field-lbl">New Name *</label>
            <input class="field-inp mono" :value="p.newName" @input="emit('update', { newName: ($event.target as HTMLInputElement).value })" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { TemplateItem, FileFolderPayload } from '../../../core/types'

const props = defineProps<{ item: TemplateItem }>()
const emit = defineEmits<{ update: [patch: Partial<FileFolderPayload>] }>()
const p = computed(() => props.item.payload as FileFolderPayload)
</script>
