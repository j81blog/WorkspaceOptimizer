<template>
  <BaseDialog :visible="visible" title="Restore unsaved work?" width="480px"
    @update:visible="emit('update:visible', $event)">
    <div class="dr-body">
      <p>
        An autosaved draft of <strong>{{ draft?.filename }}</strong> was found
        ({{ savedAt }}). It was never downloaded.
      </p>
      <p class="dr-note">Discarding it deletes the draft for good.</p>
    </div>
    <template #footer>
      <button class="dlg-btn" @click="emit('discard')">Discard</button>
      <button class="dlg-btn primary" @click="emit('restore')">Restore</button>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import BaseDialog from './BaseDialog.vue'
import type { Draft } from '../store/draft'

const props = defineProps<{ visible: boolean; draft: Draft | null }>()
const emit = defineEmits<{ 'update:visible': [boolean]; restore: []; discard: [] }>()

const savedAt = computed(() => props.draft ? new Date(props.draft.savedAt).toLocaleString() : '')
</script>

<style scoped>
.dr-body { padding: 18px 20px; display: flex; flex-direction: column; gap: 12px; font-size: 12px; color: var(--field-txt); line-height: 1.5; }
.dr-note { font-size: 11px; color: var(--field-label); }
</style>
