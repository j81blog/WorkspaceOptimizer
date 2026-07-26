<template>
  <BaseDialog :visible="visible" title="Imported content in this template" width="520px"
    @update:visible="emit('update:visible', $event)">

    <div class="dw-body">
      <p class="dw-lead">This template contains items imported from external sources:</p>
      <ul class="dw-list">
        <li v-for="row in provenanceStore.summary" :key="row.source.id">
          <strong>{{ row.count }} item{{ row.count === 1 ? '' : 's' }}</strong>
          {{ row.source.kind === 'marketplace' ? 'from Marketplace' : 'imported from' }}
          “{{ row.source.label }}”<span v-if="row.source.origin"> ({{ row.source.origin }})</span>
        </li>
      </ul>
      <p class="dw-note">Review them before deploying to production machines.</p>
    </div>

    <template #footer>
      <button class="dlg-btn" @click="emit('update:visible', false)">Cancel</button>
      <button class="dlg-btn primary" @click="emit('confirm')">Download anyway</button>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import BaseDialog from './BaseDialog.vue'
import { provenanceStore } from '../store/provenance'

defineProps<{ visible: boolean }>()
const emit = defineEmits<{ 'update:visible': [boolean]; confirm: [] }>()
</script>

<style scoped>
.dw-body { padding: 18px 20px; display: flex; flex-direction: column; gap: 12px; }
.dw-lead { font-size: 12px; color: var(--field-txt); }
.dw-list { display: flex; flex-direction: column; gap: 6px; margin-left: 18px; font-size: 12px; color: var(--field-txt); line-height: 1.5; }
.dw-note { font-size: 11px; color: var(--field-label); }
</style>
