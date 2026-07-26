<template>
  <BaseDialog :visible="visible" title="Import .reg file" width="920px" :scroll-body="false"
    @update:visible="emit('update:visible', $event)">

    <template #header-extra>
      <div class="wiz-steps">
        <span v-for="(label, i) in STEPS" :key="label" class="wiz-step" :class="{ on: step === i + 1, done: step > i + 1 }">
          {{ i + 1 }}. {{ label }}
        </span>
      </div>
    </template>

    <div class="wiz-body">
      <!-- 1: pick a file -->
      <div v-if="step === 1" class="wiz-pane">
        <p class="wiz-lead">Choose a <span class="mono">.reg</span> file exported from Registry Editor, or written by hand.</p>
        <input ref="fileInput" type="file" accept=".reg" class="wiz-file" @change="onFile" />
        <p v-if="error" class="wiz-error">{{ error }}</p>
        <p class="wiz-hint">Files are read in your browser and never uploaded. Maximum size {{ mb(MAX_REG_BYTES) }}.</p>
      </div>

      <!-- 2: defaults -->
      <div v-else-if="step === 2" class="wiz-pane wiz-pane--scroll">
        <p class="wiz-lead">
          Read <strong>{{ entries.length }}</strong> registry
          {{ entries.length === 1 ? 'value' : 'values' }} from <span class="mono">{{ filename }}</span>
          <span v-if="encoding"> ({{ encoding }})</span>.
        </p>
        <p v-if="error" class="wiz-error">{{ error }}</p>

        <template v-if="!error">
          <div class="wiz-grid">
            <label class="wiz-field">
              <span class="field-lbl">Category *</span>
              <input class="field-inp" v-model="category" placeholder="Imported" />
            </label>
            <label class="wiz-field">
              <span class="field-lbl">Deploy order</span>
              <input class="field-inp" inputmode="numeric" :value="order"
                @input="order = Number(($event.target as HTMLInputElement).value.replace(/\D/g, '')) || 0" />
            </label>
          </div>
          <p v-if="!category.trim()" class="wiz-error">A category is required.</p>

          <div class="wiz-os">
            <div class="wiz-os-hdr">Run on</div>
            <label v-for="os in supportedOs" :key="os.tag" class="wiz-os-row">
              <input type="checkbox" :checked="!!osPick[os.tag]" @change="toggleOs(os.tag, ($event.target as HTMLInputElement).checked)" />
              <span>{{ os.name }}</span>
            </label>
            <p v-if="noOsSelected" class="wiz-warn">No operating system selected, so these items will not run anywhere.</p>
          </div>

          <details v-if="warnings.length" class="wiz-warnings">
            <summary>{{ warnings.length }} parser {{ warnings.length === 1 ? 'warning' : 'warnings' }}</summary>
            <ul>
              <li v-for="(w, i) in warnings" :key="i">
                <span class="mono">line {{ w.line }}</span>: {{ w.message }}
              </li>
            </ul>
          </details>
        </template>
      </div>

      <!-- 3: review -->
      <div v-else-if="step === 3" class="wiz-pane-flush">
        <!-- A .reg file supplies no name, category or order, so all three are editable. -->
        <MergeTable v-if="plan" :rows="plan.rows" :editable-name="true" :show-category="true" :show-order="true" />
      </div>
    </div>

    <template #footer>
      <span class="wiz-count" v-if="step === 3 && plan">{{ selectedCount }} selected</span>
      <button class="dlg-btn" @click="emit('update:visible', false)">Cancel</button>
      <button v-if="step > 1" class="dlg-btn" @click="back">Back</button>
      <button v-if="step < 3" class="dlg-btn primary" :disabled="!canAdvance" @click="next">Next</button>
      <button v-else class="dlg-btn primary" :disabled="selectedCount === 0" @click="onImport">
        Import {{ selectedCount }} item{{ selectedCount === 1 ? '' : 's' }}
      </button>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseDialog from './BaseDialog.vue'
import MergeTable from './MergeTable.vue'
import { documentStore } from '../store/document'
import {
  parseRegBuffer, regEntriesToItems, MAX_REG_BYTES, MAX_REG_ENTRIES,
  type RegParseEntry, type RegParseWarning, type RegEncoding
} from '../core/regParser'
import { buildMergePlan, type MergePlan } from '../core/merge'
import type { OsMapping } from '../core/types'

const STEPS = ['File', 'Defaults', 'Review']

const props = defineProps<{ visible: boolean }>()
const emit = defineEmits<{
  'update:visible': [boolean]
  confirm: [plan: MergePlan, filename: string]
}>()

const step = ref(1)
const fileInput = ref<HTMLInputElement | null>(null)
const filename = ref('')
const encoding = ref<RegEncoding | ''>('')
const entries = ref<RegParseEntry[]>([])
const warnings = ref<RegParseWarning[]>([])
const error = ref('')

const category = ref('Imported')
const order = ref(100)
const osPick = ref<Record<string, boolean>>({})
const plan = ref<MergePlan | null>(null)

const supportedOs = computed(() => documentStore.document?.supportedOs ?? [])
const noOsSelected = computed(() => !Object.values(osPick.value).some(Boolean))
const selectedCount = computed(() => plan.value?.rows.filter(r => r.selected).length ?? 0)

const canAdvance = computed(() => {
  if (step.value === 1) return entries.value.length > 0 && !error.value
  if (step.value === 2) return !error.value && category.value.trim().length > 0
  return true
})

// Reset to a clean wizard every time it opens, including on an already-open mount.
watch(() => props.visible, (v) => {
  if (!v) return
  step.value = 1
  filename.value = ''
  encoding.value = ''
  entries.value = []
  warnings.value = []
  error.value = ''
  category.value = 'Imported'
  order.value = 100
  plan.value = null
  osPick.value = Object.fromEntries(supportedOs.value.map(o => [o.tag, true]))
}, { immediate: true })

function mb(bytes: number): string {
  return `${Math.round(bytes / (1024 * 1024))} MB`
}

function toggleOs(tag: string, on: boolean) {
  osPick.value = { ...osPick.value, [tag]: on }
}

async function onFile(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file) return

  error.value = ''
  entries.value = []
  warnings.value = []
  filename.value = file.name

  // Size check first: rejecting a registry dump before reading it keeps the tab responsive.
  if (file.size > MAX_REG_BYTES) {
    error.value = `${file.name} is ${(file.size / (1024 * 1024)).toFixed(1)} MB. The maximum supported size is ${mb(MAX_REG_BYTES)}. Split the file or trim it in a text editor.`
    return
  }

  try {
    const result = parseRegBuffer(await file.arrayBuffer())
    entries.value = result.entries
    warnings.value = result.warnings
    encoding.value = result.encoding

    if (result.entries.length === 0) {
      error.value = 'No registry values were found in this file.'
      return
    }
    if (result.entries.length > MAX_REG_ENTRIES) {
      error.value = `This file contains ${result.entries.length.toLocaleString()} registry values. Import is limited to ${MAX_REG_ENTRIES.toLocaleString()}. Split the file or trim it in a text editor.`
      return
    }
    step.value = 2
  } catch (err) {
    error.value = 'Could not read that file: ' + (err as Error).message
  }
}

function buildPlan() {
  const os: Record<string, OsMapping> = {}
  for (const [tag, on] of Object.entries(osPick.value)) {
    if (on) os[tag] = { execute: true, physical: true, virtual: true }
  }
  const items = regEntriesToItems(
    entries.value,
    { category: category.value.trim(), order: order.value, os },
    filename.value
  )
  // Run .reg rows through the same duplicate/conflict detection as snippets, so
  // importing the same file twice does not silently double every item.
  plan.value = buildMergePlan(
    documentStore.document ?? { metadata: null, supportedOs: [], items: [] },
    items
  )
}

function next() {
  if (!canAdvance.value) return
  if (step.value === 2) buildPlan()
  step.value++
}

function back() {
  step.value--
}

function onImport() {
  if (plan.value && selectedCount.value > 0) emit('confirm', plan.value, filename.value)
}
</script>

<style scoped>
.wiz-steps { display: flex; gap: 14px; }
.wiz-step { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; color: var(--field-label); }
.wiz-step.on { color: var(--item-bar); }
.wiz-step.done { color: var(--field-txt); }
.wiz-body { display: flex; flex-direction: column; flex: 1; min-height: 0; }
.wiz-pane { padding: 20px; display: flex; flex-direction: column; gap: 14px; }
.wiz-pane--scroll { overflow-y: auto; }
.wiz-pane-flush { display: flex; flex-direction: column; flex: 1; min-height: 0; }
.wiz-lead { font-size: 12px; color: var(--field-txt); }
.wiz-hint { font-size: 11px; color: var(--field-label); }
.wiz-error { font-size: 11px; color: var(--btn-danger-txt); background: var(--btn-danger-bg); border: 1px solid var(--btn-danger-bdr); border-radius: 6px; padding: 8px 10px; line-height: 1.5; }
.wiz-warn { font-size: 11px; color: #f59e0b; margin-top: 6px; }
.wiz-file { font-size: 12px; color: var(--field-txt); font-family: 'Montserrat', sans-serif; }
.wiz-grid { display: grid; grid-template-columns: 1fr 140px; gap: 12px; }
.wiz-field { display: flex; flex-direction: column; gap: 4px; }
.wiz-os { border: 1px solid var(--card-border); border-radius: 6px; padding: 12px; }
.wiz-os-hdr { font-size: 9.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; color: var(--field-label); margin-bottom: 8px; }
.wiz-os-row { display: flex; align-items: center; gap: 8px; font-size: 12px; color: var(--field-txt); cursor: pointer; padding: 3px 0; }
.wiz-warnings { font-size: 11px; color: var(--field-label); }
.wiz-warnings summary { cursor: pointer; }
.wiz-warnings ul { margin: 8px 0 0 16px; display: flex; flex-direction: column; gap: 3px; }
.wiz-count { font-size: 11px; color: var(--field-label); flex: 1; }
</style>
