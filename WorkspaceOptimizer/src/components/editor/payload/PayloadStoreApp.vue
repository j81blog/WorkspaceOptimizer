<template>
  <div class="card">
    <div class="card-hdr">
      <div class="c-accent" style="background:#f472b6"></div>
      <span class="c-label">Store App</span>
    </div>
    <div class="card-body">
      <div class="field-grid">
        <div class="col-12">
          <div class="field">
            <label class="field-lbl">Package Name *</label>
            <input class="field-inp" :value="p.name" @input="emit('update', { name: ($event.target as HTMLInputElement).value })" placeholder="e.g. Microsoft.BingWeather" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { TemplateItem, StoreAppPayload } from '../../../core/types'

const props = defineProps<{ item: TemplateItem }>()
const emit = defineEmits<{ update: [patch: Partial<StoreAppPayload>] }>()
const p = computed(() => props.item.payload as StoreAppPayload)
</script>
