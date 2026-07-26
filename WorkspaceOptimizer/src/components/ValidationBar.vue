<template>
  <div class="val-root">
    <div class="val-bar" :class="statusClass" @click="expanded = !expanded">
      <span class="val-icon">{{ icon }}</span>
      <span class="val-text">{{ label }}</span>
      <span class="val-toggle">{{ expanded ? '▲' : '▼' }}</span>
    </div>
    <div v-if="expanded && issues.length" class="val-list">
      <div v-for="issue in issues" :key="issue.code + issue.path"
        class="val-issue" :class="issue.severity.toLowerCase()"
        @click.stop="onIssueClick(issue)">
        <span class="vi-sev">{{ issue.severity === 'Error' ? '✕' : '⚠' }}</span>
        <span class="vi-msg">{{ issue.message }}</span>
        <span class="vi-path">{{ issue.path }}</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { documentStore } from '../store/document'
import { uiStore } from '../store/ui'
import type { ValidationIssue } from '../core/types'

const emit = defineEmits<{ properties: [] }>()

const expanded = ref(false)
const result = computed(() => documentStore.validationResult)
const issues = computed(() => [...result.value.errors, ...result.value.warnings])
const statusClass = computed(() => result.value.errors.length ? 'has-errors' : result.value.warnings.length ? 'has-warnings' : 'is-valid')
const icon = computed(() => result.value.errors.length ? '✕' : result.value.warnings.length ? '⚠' : '✓')
const label = computed(() => {
  const e = result.value.errors.length, w = result.value.warnings.length
  if (!e && !w) return 'Valid'
  return [e && `${e} error${e !== 1 ? 's' : ''}`, w && `${w} warning${w !== 1 ? 's' : ''}`].filter(Boolean).join(', ')
})

/** Take the user to wherever the problem can actually be fixed. */
function onIssueClick(issue: ValidationIssue) {
  if (issue.code === 'META_REQUIRED') emit('properties')
  else if (issue.itemId) uiStore.select(issue.itemId)
}
</script>

<style scoped>
.val-root { flex-shrink: 0; }
.val-bar { display: flex; align-items: center; gap: 8px; height: 32px; padding: 0 16px; font-size: 11px; font-weight: 700; cursor: pointer; border-top: 1px solid var(--card-border); }
.val-bar.is-valid { background: rgba(45,212,191,0.08); color: #2dd4bf; }
.val-bar.has-warnings { background: rgba(251,191,36,0.08); color: #fbbf24; }
.val-bar.has-errors { background: rgba(248,113,113,0.08); color: #f87171; }
.val-toggle { margin-left: auto; font-size: 9px; }
.val-list { background: var(--card-bg); border-top: 1px solid var(--card-border); max-height: 180px; overflow-y: auto; }
.val-issue { display: flex; align-items: baseline; gap: 8px; padding: 6px 16px; font-size: 11px; cursor: pointer; border-bottom: 1px solid var(--sb-border); }
.val-issue:hover { background: var(--item-hover); }
.val-issue.error { color: #f87171; }
.val-issue.warning { color: #fbbf24; }
.vi-sev { flex-shrink: 0; font-size: 10px; }
.vi-msg { flex: 1; }
.vi-path { font-size: 9px; opacity: 0.6; }
</style>
