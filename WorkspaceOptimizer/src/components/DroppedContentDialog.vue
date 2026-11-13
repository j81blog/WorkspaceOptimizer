<template>
  <BaseDialog :visible="visible" title="Some content will not be kept" width="520px"
    @update:visible="emit('update:visible', $event)">
    <div class="dc-body">
      <p>
        This file contains content the editor cannot keep. It is not part of the open
        template and will be missing when you save it:
      </p>
      <ul class="dc-list">
        <li v-for="(line, i) in shown" :key="i">{{ line }}</li>
        <li v-if="items.length > shown.length">and {{ items.length - shown.length }} more</li>
      </ul>
      <p class="dc-note">Keep the original file if you need this content.</p>
    </div>
    <template #footer>
      <button class="dlg-btn primary" @click="emit('update:visible', false)">OK</button>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import BaseDialog from './BaseDialog.vue'

const props = defineProps<{ visible: boolean; items: string[] }>()
const emit = defineEmits<{ 'update:visible': [boolean] }>()

const shown = computed(() => props.items.slice(0, 15))
</script>

<style scoped>
.dc-body { padding: 18px 20px; display: flex; flex-direction: column; gap: 12px; font-size: 12px; color: var(--field-txt); line-height: 1.5; }
.dc-list { margin-left: 18px; display: flex; flex-direction: column; gap: 4px; }
.dc-note { font-size: 11px; color: var(--field-label); }
</style>
