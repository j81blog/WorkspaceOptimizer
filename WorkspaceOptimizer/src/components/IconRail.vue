<template>
  <nav class="rail">
    <img :src="brand.logo" class="rail-logo" :alt="brand.name" @error="onLogoError" />

    <button class="rail-btn" data-tooltip="Create a new template from built-in defaults" @click="emit('new')">
      <svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="12" y1="18" x2="12" y2="12"/><line x1="9" y1="15" x2="15" y2="15"/></svg>
    </button>
    <button class="rail-btn" data-tooltip="Open an existing XML template file" @click="emit('open')">
      <svg viewBox="0 0 24 24"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
    </button>
    <button class="rail-btn" :class="{ disabled: !canDownloadXml }" data-tooltip="Download the template as an XML file"
      @click="canDownloadXml && emit('save')">
      <svg viewBox="0 0 24 24"><polyline points="8 17 12 21 16 17"/><line x1="12" y1="12" x2="12" y2="21"/><path d="M20.88 18.09A5 5 0 0 0 18 9h-1.26A8 8 0 1 0 3 16.29"/></svg>
    </button>
    <button class="rail-btn" data-tooltip="Download the PowerShell deployment script" @click="emit('downloadscript')">
      <svg class="icon-filled" viewBox="0 0 24 24"><path d="M21.83,4C22.32,4 22.63,4.4 22.5,4.89L19.34,19.11C19.23,19.6 18.75,20 18.26,20H2.17C1.68,20 1.37,19.6 1.5,19.11L4.66,4.89C4.77,4.4 5.25,4 5.74,4H21.83M15.83,16H11.83C11.37,16 11,16.38 11,16.84C11,17.31 11.37,17.69 11.83,17.69H15.83C16.3,17.69 16.68,17.31 16.68,16.84C16.68,16.38 16.3,16 15.83,16M5.78,16.28C5.38,16.56 5.29,17.11 5.57,17.5C5.85,17.92 6.41,18 6.81,17.73C14.16,12.56 14.21,12.5 14.26,12.47C14.44,12.31 14.53,12.09 14.54,11.87C14.55,11.67 14.5,11.5 14.38,11.31L9.46,6.03C9.13,5.67 8.57,5.65 8.21,6C7.85,6.32 7.83,6.88 8.16,7.24L12.31,11.68L5.78,16.28Z"/></svg>
    </button>

    <div class="rail-divider"></div>

    <button class="rail-btn" data-tooltip="Add, edit or remove supported operating systems" @click="emit('manageos')">
      <svg viewBox="0 0 24 24"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
    </button>
    <button class="rail-btn" :class="{ disabled: !canPdf }" data-tooltip="Generate a PDF summary report"
      @click="canPdf && emit('pdf')">
      <svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>
    </button>
    <button class="rail-btn" data-tooltip="About this application" @click="emit('about')">
      <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
    </button>

    <div class="rail-spacer"></div>
    <div class="rail-divider"></div>

    <button class="rail-btn" :data-tooltip="isDark ? 'Switch to light theme' : 'Switch to dark theme'" @click="toggleTheme">
      <svg v-if="isDark" viewBox="0 0 24 24"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>
      <svg v-else viewBox="0 0 24 24"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
    </button>
    <button class="rail-btn" data-tooltip="Toggle the item explorer" @click="emit('togglesidebar')">
      <svg viewBox="0 0 24 24"><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/></svg>
    </button>
  </nav>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { documentStore } from '../store/document'
import { brand, onLogoError } from '../branding'

const emit = defineEmits<{
  new: []; open: []; save: []; downloadscript: []; manageos: []; pdf: []; about: []; togglesidebar: []
}>()

const canDownloadXml = computed(() =>
  !!documentStore.document?.items.length &&
  !!documentStore.document?.supportedOs.length &&
  !documentStore.hasErrors)
const canPdf = computed(() =>
  !!documentStore.document?.items.length && !!documentStore.document?.supportedOs.length)

const isDark = ref(true)
const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')

function applyTheme() {
  document.documentElement.setAttribute('data-theme', isDark.value ? 'dark' : 'light')
}
function onSystemChange(e: MediaQueryListEvent) {
  if (!localStorage.getItem('theme')) { isDark.value = e.matches; applyTheme() }
}
function toggleTheme() {
  isDark.value = !isDark.value
  applyTheme()
  localStorage.setItem('theme', isDark.value ? 'dark' : 'light')
}

onMounted(() => {
  const saved = localStorage.getItem('theme')
  isDark.value = saved ? saved !== 'light' : mediaQuery.matches
  applyTheme()
  mediaQuery.addEventListener('change', onSystemChange)
})
onUnmounted(() => mediaQuery.removeEventListener('change', onSystemChange))
</script>

<style scoped>
.rail {
  width: 56px; min-width: 56px; height: 100%;
  background: var(--rail-bg); border-right: 1px solid var(--sb-border);
  display: flex; flex-direction: column; align-items: center;
  padding: 8px 0; gap: 2px; z-index: 10; position: relative;
}
.rail-logo { width: 32px; height: 32px; border-radius: 8px; object-fit: contain; margin-bottom: 6px; flex-shrink: 0; }
.rail-divider { width: 32px; height: 1px; background: var(--sb-input-bdr); margin: 4px 0; flex-shrink: 0; }
.rail-spacer { flex: 1; }
.rail-btn {
  width: 40px; height: 40px; border-radius: 6px;
  background: transparent; border: none; color: var(--sb-select-txt);
  display: flex; align-items: center; justify-content: center;
  cursor: pointer; position: relative; transition: background 0.15s, color 0.15s; flex-shrink: 0;
}
.rail-btn:hover { background: var(--rail-hover); color: var(--item-bar); }
.rail-btn.disabled { opacity: 0.35; cursor: not-allowed; }
.rail-btn.disabled:hover { background: transparent; color: var(--sb-select-txt); }
.rail-btn svg { width: 18px; height: 18px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
.rail-btn svg.icon-filled { fill: currentColor; stroke: none; }
</style>
