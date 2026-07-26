<template>
  <BaseDialog :visible="visible" title="What's New" width="600px"
    @update:visible="emit('update:visible', $event)">

    <div class="wn-body">
      <template v-for="(line, i) in lines" :key="i">
        <div v-if="line.kind === 'version'" class="wn-version">{{ line.text }}</div>
        <div v-else-if="line.kind === 'section'" class="wn-section">{{ line.text }}</div>
        <div v-else-if="line.kind === 'entry'" class="wn-entry">
          <span class="wn-tag" :class="'wn-tag--' + line.tag!.toLowerCase()">{{ line.tag }}</span>
          <span class="wn-text">{{ line.text }}</span>
        </div>
        <p v-else-if="line.text" class="wn-para">{{ line.text }}</p>
      </template>
    </div>

    <template #footer>
      <button class="dlg-btn primary" @click="emit('update:visible', false)">Close</button>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import BaseDialog from './BaseDialog.vue'
import changelogRaw from '../../../CHANGELOG.md?raw'

defineProps<{ visible: boolean }>()
const emit = defineEmits<{ 'update:visible': [boolean] }>()

interface Line {
  kind: 'version' | 'section' | 'entry' | 'text'
  text: string
  tag?: string
}

/**
 * Deliberately not a markdown renderer. The changelog's `NEW:` / `FIX:` / `CHANGE:`
 * convention exists so this stays a handful of lines; anything unrecognized falls
 * through as plain text, which keeps the file readable on GitHub too.
 */
const lines = computed<Line[]>(() =>
  changelogRaw.split(/\r?\n/).flatMap<Line>(raw => {
    const line = raw.trim()
    if (!line || line.startsWith('# ')) return []
    // Order matters: '### ' also starts with '## '.
    if (line.startsWith('### ')) return [{ kind: 'section', text: line.slice(4).trim() }]
    if (line.startsWith('## ')) return [{ kind: 'version', text: line.slice(3).trim() }]

    const m = line.match(/^(NEW|FIX|CHANGE):\s*(.+)$/)
    if (m) return [{ kind: 'entry', tag: m[1], text: m[2] }]

    return [{ kind: 'text', text: line }]
  })
)
</script>

<style scoped>
.wn-body { padding: 18px 20px; display: flex; flex-direction: column; gap: 7px; }
.wn-version {
  font-size: 12px; font-weight: 700; color: var(--bc-name);
  border-bottom: 1px solid var(--card-border); padding-bottom: 6px;
  margin-top: 10px;
}
.wn-version:first-child { margin-top: 0; }
.wn-section {
  font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px;
  color: var(--field-label); margin-top: 12px;
}
.wn-entry { display: flex; align-items: flex-start; gap: 9px; font-size: 12px; line-height: 1.5; }
.wn-tag {
  flex-shrink: 0; min-width: 54px; text-align: center;
  font-size: 9px; font-weight: 700; letter-spacing: 0.4px;
  padding: 2px 6px; border-radius: 3px; margin-top: 2px;
}
.wn-tag--new { background: #1d4e3a; color: #6fcf97; }
.wn-tag--fix { background: #4a1a1a; color: #ff8a8a; }
.wn-tag--change { background: #2a2050; color: #b39ddb; }
[data-theme="light"] .wn-tag--new { background: #dcfce7; color: #15803d; }
[data-theme="light"] .wn-tag--fix { background: #fee2e2; color: #b91c1c; }
[data-theme="light"] .wn-tag--change { background: #faf5ff; color: #7c3aed; }
.wn-text { color: var(--field-txt); }
.wn-para { font-size: 11px; color: var(--field-label); line-height: 1.6; }
</style>
