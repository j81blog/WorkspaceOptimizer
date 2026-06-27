<template>
  <div class="card">
    <div class="card-hdr">
      <div class="c-accent" style="background:#a78bfa"></div>
      <span class="c-label">Scheduled Task</span>
    </div>
    <div class="card-body">
      <div class="field-grid">
        <div class="col-9">
          <div class="field">
            <label class="field-lbl">Task Name *</label>
            <input class="field-inp" :value="p.name" @input="emit('update', { name: ($event.target as HTMLInputElement).value })" />
          </div>
        </div>
        <div class="col-3">
          <div class="field">
            <label class="field-lbl">Action *</label>
            <select class="field-inp" :value="p.action" @change="emit('update', { action: ($event.target as HTMLSelectElement).value })">
              <option>Disabled</option><option>Enabled</option>
            </select>
          </div>
        </div>
      </div>
      <div class="field-grid">
        <div class="col-12">
          <div class="field">
            <label class="field-lbl">Path *</label>
            <input class="field-inp mono" :value="p.path" @input="emit('update', { path: ($event.target as HTMLInputElement).value })" placeholder="\Microsoft\Windows\UpdateOrchestrator" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { TemplateItem, ScheduledTaskPayload } from '../../../core/types'

const props = defineProps<{ item: TemplateItem }>()
const emit = defineEmits<{ update: [patch: Partial<ScheduledTaskPayload>] }>()
const p = computed(() => props.item.payload as ScheduledTaskPayload)
</script>
