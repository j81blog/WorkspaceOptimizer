<template>
  <div class="card">
    <div class="card-hdr">
      <div class="c-accent" style="background:#ea7a2e"></div>
      <span class="c-label">Registry</span>
    </div>
    <div class="card-body">
      <div class="field-grid">
        <div class="col-5">
          <div class="field">
            <label class="field-lbl">Action *</label>
            <select class="field-inp" :value="p.action" @change="emit('update', { action: ($event.target as HTMLSelectElement).value })">
              <option>SetValue</option><option>DeleteKey</option><option>DeleteKeyRecursively</option><option>DeleteValue</option>
            </select>
          </div>
        </div>
        <div v-if="p.action === 'SetValue'" class="col-4">
          <div class="field">
            <label class="field-lbl">Type *</label>
            <select class="field-inp" :value="p.registryType" @change="emit('update', { registryType: ($event.target as HTMLSelectElement).value })">
              <option>DWord</option><option>String</option><option>ExpandString</option><option>MultiString</option><option>Qword</option><option>Binary</option>
            </select>
          </div>
        </div>
        <div class="col-3">
          <div class="field">
            <label class="field-lbl">Hive *</label>
            <select class="field-inp" :value="p.hive" @change="emit('update', { hive: ($event.target as HTMLSelectElement).value })">
              <option>HKLM</option><option>HKCU</option><option>HKU</option><option value="HKU\DefaultUser">HKU\DefaultUser</option>
            </select>
          </div>
        </div>
      </div>
      <div class="field-grid">
        <div class="col-12">
          <div class="field">
            <label class="field-lbl">Path *</label>
            <input class="field-inp mono" :value="p.path" @input="emit('update', { path: ($event.target as HTMLInputElement).value })" placeholder="SOFTWARE\Policies\…" />
          </div>
        </div>
      </div>
      <div class="field-grid">
        <div v-if="needsName" class="col-9">
          <div class="field">
            <label class="field-lbl">Value Name *</label>
            <input class="field-inp mono" :value="p.name" @input="emit('update', { name: ($event.target as HTMLInputElement).value })" />
          </div>
        </div>
        <div v-if="p.action === 'SetValue'" class="col-3">
          <div class="field">
            <label class="field-lbl">Value *</label>
            <textarea v-if="isMultiline" class="field-inp field-ta mono" :value="p.value"
              @input="emit('update', { value: ($event.target as HTMLTextAreaElement).value })"
              :placeholder="valuePlaceholder" rows="3" />
            <input v-else class="field-inp mono" :value="p.value"
              @input="emit('update', { value: ($event.target as HTMLInputElement).value })"
              :placeholder="valuePlaceholder" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { TemplateItem, RegistryPayload } from '../../../core/types'

const props = defineProps<{ item: TemplateItem }>()
const emit = defineEmits<{ update: [patch: Partial<RegistryPayload>] }>()
const p = computed(() => props.item.payload as RegistryPayload)
const needsName = computed(() => ['SetValue','DeleteValue'].includes(p.value.action))
const isMultiline = computed(() => ['multistring', 'binary'].includes(p.value.registryType?.toLowerCase()))
const valuePlaceholder = computed(() => {
  const t = p.value.registryType?.toLowerCase()
  if (t === 'dword') return '0 or 0x00000001'
  if (t === 'binary') return 'FF 00 AB CD'
  if (t === 'multistring') return 'value1\nvalue2\nvalue3'
  return ''
})
</script>

<style scoped>
.field-ta { resize: vertical; min-height: 60px; font-size: 12px; font-family: 'Montserrat', sans-serif; }
</style>
