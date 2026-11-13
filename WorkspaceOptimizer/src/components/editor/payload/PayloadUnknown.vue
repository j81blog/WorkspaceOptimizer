<template>
  <div class="card">
    <div class="card-hdr">
      <div class="c-accent" style="background:#94a3b8"></div>
      <span class="c-label">{{ item.typeRaw || 'Unknown' }}</span>
    </div>
    <div class="card-body">
      <p class="unk-note">Not supported by this editor version, saved unchanged.</p>
      <textarea v-if="raw" class="field-inp field-ta mono" :value="raw" readonly rows="6" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { TemplateItem } from '../../../core/types'

const props = defineProps<{ item: TemplateItem }>()
const raw = computed(() => props.item.payload.type === 'Unknown' ? props.item.payload.rawXml : '')
</script>

<style scoped>
.unk-note { font-size: 12px; color: var(--field-label); margin-bottom: 8px; }
.field-ta { resize: vertical; font-size: 12px; }
</style>
