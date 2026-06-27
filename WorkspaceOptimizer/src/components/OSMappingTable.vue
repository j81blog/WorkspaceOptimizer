<template>
  <div class="card" v-if="supportedOs.length">
    <div class="card-hdr">
      <div class="c-accent" style="background:#0ea5e9"></div>
      <span class="c-label">Client OS</span>
    </div>
    <div class="card-body os-section" v-if="clientOs.length">
      <div class="os-col-headers">
        <span class="os-col-os">OS</span>
        <span class="os-col-chk">Execute</span>
        <span class="os-col-chk">Physical</span>
        <span class="os-col-chk">Virtual</span>
      </div>
      <div v-for="os in clientOs" :key="os.tag" class="os-row">
        <label class="os-name-cell">
          <input type="checkbox" :checked="isSupported(os.tag)" @change="toggleSupported(os.tag, ($event.target as HTMLInputElement).checked)" />
          <span>{{ os.name }}</span>
        </label>
        <input type="checkbox" class="os-chk" :disabled="!isSupported(os.tag)" :checked="get(os.tag, 'execute')" @change="setField(os.tag, 'execute', ($event.target as HTMLInputElement).checked)" />
        <input type="checkbox" class="os-chk" :disabled="!isSupported(os.tag)" :checked="get(os.tag, 'physical')" @change="setField(os.tag, 'physical', ($event.target as HTMLInputElement).checked)" />
        <input type="checkbox" class="os-chk" :disabled="!isSupported(os.tag)" :checked="get(os.tag, 'virtual')" @change="setField(os.tag, 'virtual', ($event.target as HTMLInputElement).checked)" />
      </div>
    </div>
    <div v-else class="card-body"><p class="os-empty">No client OS entries defined.</p></div>

    <div class="card-hdr" style="border-top: 1px solid var(--card-hdr-border)">
      <div class="c-accent" style="background:#a78bfa"></div>
      <span class="c-label">Server OS</span>
    </div>
    <div class="card-body os-section" v-if="serverOs.length">
      <div class="os-col-headers">
        <span class="os-col-os">OS</span>
        <span class="os-col-chk">Execute</span>
        <span class="os-col-chk">Physical</span>
        <span class="os-col-chk">Virtual</span>
      </div>
      <div v-for="os in serverOs" :key="os.tag" class="os-row">
        <label class="os-name-cell">
          <input type="checkbox" :checked="isSupported(os.tag)" @change="toggleSupported(os.tag, ($event.target as HTMLInputElement).checked)" />
          <span>{{ os.name }}</span>
        </label>
        <input type="checkbox" class="os-chk" :disabled="!isSupported(os.tag)" :checked="get(os.tag, 'execute')" @change="setField(os.tag, 'execute', ($event.target as HTMLInputElement).checked)" />
        <input type="checkbox" class="os-chk" :disabled="!isSupported(os.tag)" :checked="get(os.tag, 'physical')" @change="setField(os.tag, 'physical', ($event.target as HTMLInputElement).checked)" />
        <input type="checkbox" class="os-chk" :disabled="!isSupported(os.tag)" :checked="get(os.tag, 'virtual')" @change="setField(os.tag, 'virtual', ($event.target as HTMLInputElement).checked)" />
      </div>
    </div>
    <div v-else class="card-body"><p class="os-empty">No server OS entries defined.</p></div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { documentStore } from '../store/document'
import type { TemplateItem, OsMapping } from '../core/types'

const props = defineProps<{ item: TemplateItem }>()

const supportedOs = computed(() => documentStore.document?.supportedOs ?? [])
const clientOs = computed(() => supportedOs.value.filter(o => !o.isServerOs))
const serverOs = computed(() => supportedOs.value.filter(o => o.isServerOs))

function isSupported(tag: string): boolean {
  return tag in props.item.os
}

function get(tag: string, field: keyof OsMapping): boolean {
  return props.item.os[tag]?.[field] ?? false
}

function toggleSupported(tag: string, checked: boolean) {
  const newOs = { ...props.item.os }
  if (checked) {
    newOs[tag] = { execute: false, physical: false, virtual: false }
  } else {
    delete newOs[tag]
  }
  documentStore.updateItem(props.item.id, { os: newOs })
}

function setField(tag: string, field: keyof OsMapping, value: boolean) {
  if (!isSupported(tag)) return
  const current = { ...props.item.os[tag] }
  current[field] = value

  // Enforce: if physical=false AND virtual=false → execute must be false
  if (!current.physical && !current.virtual) current.execute = false

  const newOs = { ...props.item.os, [tag]: current }
  documentStore.updateItem(props.item.id, { os: newOs })
}
</script>

<style scoped>
.os-section { padding: 10px 14px; }
.os-col-headers { display: grid; grid-template-columns: 1fr 70px 70px 70px; gap: 4px; padding: 4px 0 6px; font-size: 9px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; color: var(--os-hdr-txt); border-bottom: 1px solid var(--os-border); margin-bottom: 4px; }
.os-col-chk { text-align: center; }
.os-row { display: grid; grid-template-columns: 1fr 70px 70px 70px; gap: 4px; align-items: center; padding: 5px 0; border-bottom: 1px solid var(--os-border); }
.os-row:last-child { border-bottom: none; }
.os-row:hover { background: var(--os-row-hover); }
.os-name-cell { display: flex; align-items: center; gap: 8px; font-size: 12px; color: var(--field-txt); cursor: pointer; }
.os-chk { display: block; margin: 0 auto; cursor: pointer; accent-color: var(--item-bar); width: 15px; height: 15px; border-radius: 4px; }
.os-chk:disabled { opacity: 0.3; cursor: not-allowed; }
.os-empty { font-size: 11px; color: var(--field-label); }
</style>
