<template>
  <BaseDialog :visible="visible" :title="`Import from ${source?.label ?? ''}`" width="920px"
    :scroll-body="false" @update:visible="emit('update:visible', $event)">

    <div v-if="plan" class="mp-body">
      <div v-if="plan.missingOs.length" class="mp-os">
        <div class="mp-os-hdr">Operating systems not in this template</div>
        <div v-for="m in plan.missingOs" :key="m.tag" class="mp-os-row">
          <label class="mp-os-add">
            <input type="checkbox" :checked="m.accepted" @change="m.accepted = ($event.target as HTMLInputElement).checked" />
            <span>Add <strong>{{ m.definition.name }}</strong> (<span class="mono">{{ m.tag }}</span>) to Supported OS</span>
          </label>
          <div v-if="!m.complete" class="mp-os-note">
            This source supplied no build numbers for <span class="mono">{{ m.tag }}</span>, so it
            is added disabled. Set its builds in <strong>Manage OS</strong>, then enable the
            items you want to run on it.
          </div>
          <div v-if="!m.accepted" class="mp-os-warn">
            Leave unticked and <span class="mono">{{ m.tag }}</span> is removed from imported items.
          </div>
        </div>
      </div>

      <!-- Category and order depend on the destination template, so both are editable
           here. Names are left as the snippet's author wrote them. -->
      <MergeTable :rows="plan.rows" :show-category="true" :show-order="true" />
    </div>

    <template #footer>
      <div class="mp-foot">
        <div v-if="source && !source.sameOrigin" class="trust-bar">
          <div class="trust-msg">
            ⚠ This content comes from <strong>{{ source.originLabel }}</strong>, which is not part of this site.
            Imported items can change registry values, disable services and delete files.
          </div>
          <label class="trust-ack">
            <input type="checkbox" v-model="acknowledged" />
            <span>I understand and want to import from this source.</span>
          </label>
        </div>
        <div class="mp-actions">
          <button class="dlg-btn" @click="emit('update:visible', false)">Cancel</button>
          <button class="dlg-btn primary" :disabled="!canImport" @click="onImport">
            Import {{ selectedCount }} item{{ selectedCount === 1 ? '' : 's' }}
          </button>
        </div>
      </div>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseDialog from './BaseDialog.vue'
import MergeTable from './MergeTable.vue'
import type { MergePlan } from '../core/merge'
import type { ImportSource } from '../core/types'

/** Where the incoming content came from, and whether it needs an acknowledgement. */
export interface SourceDescriptor extends ImportSource {
  sameOrigin: boolean
  originLabel: string
}

const props = defineProps<{
  visible: boolean
  plan: MergePlan | null
  source: SourceDescriptor | null
}>()

const emit = defineEmits<{ 'update:visible': [boolean]; confirm: [] }>()

const acknowledged = ref(false)

// Always re-arm the acknowledgement when the dialog opens, including on an
// already-open mount, where a stale tick here would mean an unacknowledged import.
watch(() => props.visible, (v) => { if (v) acknowledged.value = false }, { immediate: true })

const selectedCount = computed(() => props.plan?.rows.filter(r => r.selected).length ?? 0)

const canImport = computed(() =>
  selectedCount.value > 0 && (props.source?.sameOrigin === true || acknowledged.value)
)

function onImport() {
  if (!canImport.value) return
  emit('confirm')
}
</script>

<style scoped>
.mp-body { display: flex; flex-direction: column; flex: 1; min-height: 0; }
.mp-os { padding: 12px 16px; border-bottom: 1px solid var(--card-border); flex-shrink: 0; }
.mp-os-hdr { font-size: 9.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; color: var(--field-label); margin-bottom: 8px; }
.mp-os-row { margin-bottom: 6px; }
.mp-os-add { display: flex; align-items: center; gap: 8px; font-size: 11px; color: var(--field-txt); cursor: pointer; }
.mp-os-warn { font-size: 11px; color: #f59e0b; margin-left: 22px; }
.mp-os-note { font-size: 10.5px; color: var(--field-label); line-height: 1.5; margin-left: 22px; }
.mp-foot { display: flex; flex-direction: column; gap: 10px; width: 100%; }
.trust-bar { border: 1px solid #b45309; background: rgba(180, 83, 9, 0.12); border-radius: 6px; padding: 10px 12px; }
.trust-msg { font-size: 11px; color: var(--field-txt); line-height: 1.5; }
.trust-ack { display: flex; align-items: center; gap: 8px; font-size: 11px; color: var(--field-txt); cursor: pointer; margin-top: 8px; font-weight: 600; }
.mp-actions { display: flex; justify-content: flex-end; gap: 10px; }
</style>
