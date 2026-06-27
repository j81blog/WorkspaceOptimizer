<template>
  <div class="item" :class="{ active: isActive }" @click="emit('select')">
    <div class="item-top">
      <img :src="iconSrc" class="item-icon" :alt="item.type" :style="{ filter: iconFilter }" />
      <span class="item-name">{{ item.name || '(unnamed)' }}</span>
      <span class="item-order-badge mono">{{ item.order }}</span>
      <span v-if="hasError" class="item-error">!</span>
    </div>
    <div v-if="item.description" class="item-desc">{{ item.description }}</div>
    <div v-if="viewMode === 'order'" class="item-meta">{{ item.category }}</div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { TemplateItem, ViewMode } from '../../core/types'
import { documentStore } from '../../store/document'

const props = defineProps<{ item: TemplateItem; isActive: boolean; viewMode: ViewMode }>()
const emit = defineEmits<{ select: [] }>()

const icons: Record<string, string> = {
  Registry: new URL('../../assets/icons/registry.svg', import.meta.url).href,
  Service: new URL('../../assets/icons/service.svg', import.meta.url).href,
  ScheduledTask: new URL('../../assets/icons/scheduled-task.svg', import.meta.url).href,
  StoreApp: new URL('../../assets/icons/store-app.svg', import.meta.url).href,
  PowerShell: new URL('../../assets/icons/powershell.svg', import.meta.url).href,
  FileFolder: new URL('../../assets/icons/file-folder.svg', import.meta.url).href,
  Unknown: new URL('../../assets/icons/unknown.svg', import.meta.url).href,
}

// CSS filter values to tint white SVG icons with type accent colors
const filters: Record<string, string> = {
  Registry: 'invert(65%) sepia(80%) saturate(400%) hue-rotate(0deg)',
  Service: 'invert(70%) sepia(60%) saturate(500%) hue-rotate(180deg)',
  ScheduledTask: 'invert(60%) sepia(60%) saturate(400%) hue-rotate(230deg)',
  StoreApp: 'invert(60%) sepia(80%) saturate(400%) hue-rotate(290deg)',
  PowerShell: 'invert(75%) sepia(50%) saturate(400%) hue-rotate(80deg)',
  FileFolder: 'invert(75%) sepia(60%) saturate(400%) hue-rotate(140deg)',
  Unknown: 'invert(60%)',
}

const iconSrc = computed(() => icons[props.item.type] ?? icons['Unknown'])
const iconFilter = computed(() => 'var(--icon-filter)')
const hasError = computed(() => documentStore.validationResult.errors.some(e => e.itemId === props.item.id))
</script>

<style scoped>
.item { padding: 7px 12px; cursor: pointer; border-left: 2px solid transparent; border-bottom: 1px solid var(--sb-border); transition: background 0.1s; }
.item:hover { background: var(--item-hover); }
.item.active { background: var(--item-active); border-left-color: var(--item-bar); }
.item-top { display: flex; align-items: center; gap: 8px; }
.item-icon { width: 16px; height: 16px; flex-shrink: 0; }
.item-name { font-size: 11.5px; font-weight: 600; color: var(--item-name); flex: 1; }
.item-order-badge { font-size: 10px; font-weight: 600; color: var(--item-desc); background: var(--sb-border); padding: 1px 5px; border-radius: 3px; flex-shrink: 0; }
.item-error { font-size: 10px; font-weight: 700; color: #f87171; background: rgba(248,113,113,0.1); padding: 1px 5px; border-radius: 3px; }
.item-desc { font-size: 10px; color: var(--item-desc); margin-left: 24px; margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.item-meta { font-size: 10px; color: var(--item-desc); margin-left: 24px; margin-top: 2px; }
</style>
