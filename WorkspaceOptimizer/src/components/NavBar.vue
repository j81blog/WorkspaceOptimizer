<template>
  <nav class="navbar">
    <div class="nav-brand">
      <img :src="brand.logo" class="nav-logo-img" :alt="brand.name" @error="onLogoError" />
      <span class="nav-title">{{ brand.name }}</span>
    </div>
    <div class="nav-actions">
      <button class="nav-btn" data-tooltip="Create a new template from built-in defaults" @click="emit('new')">New from Default</button>
      <button class="nav-btn" data-tooltip="Open an existing XML template file" @click="emit('open')">Open Template</button>
      <button class="nav-btn download" :disabled="!documentStore.document?.items.length || !documentStore.document?.supportedOs.length || documentStore.hasErrors" data-tooltip="Download the template as an XML file" @click="emit('save')">Download XML</button>
      <button class="nav-btn download" data-tooltip="Download the PowerShell deployment script" @click="downloadScript">Download Script</button>
      <div class="nav-div"></div>
      <button class="nav-btn" data-tooltip="Add, edit or remove supported operating systems" @click="emit('manageos')">Manage OS</button>
      <button class="nav-btn" :disabled="!documentStore.document?.items.length || !documentStore.document?.supportedOs.length" data-tooltip="Generate a PDF summary report" @click="emit('pdf')">PDF Report</button>
      <div class="nav-div"></div>
      <span class="nav-spacer"></span>
      <span v-if="documentStore.filename" class="nav-filename">{{ documentStore.filename }}</span>
      <span v-if="documentStore.dirty" class="nav-modified"><span class="mod-dot"></span>Modified</span>
      <button class="nav-btn" data-tooltip="About Workspace Optimizer" @click="emit('about')">About</button>
      <button class="theme-toggle" data-tooltip="Toggle light / dark theme" @click="toggleTheme">{{ isDark ? '☀ Light' : '☾ Dark' }}</button>
      <button class="nav-btn nav-hamburger" data-tooltip="Toggle sidebar" @click="emit('togglesidebar')">☰</button>
    </div>
  </nav>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { documentStore } from '../store/document'
import { brand, onLogoError } from '../branding'

const emit = defineEmits<{ new: []; open: []; save: []; manageos: []; pdf: []; about: []; togglesidebar: [] }>()
const isDark = ref(true)

const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')

function applyTheme() {
  document.documentElement.setAttribute('data-theme', isDark.value ? 'dark' : 'light')
}

function onSystemChange(e: MediaQueryListEvent) {
  if (!localStorage.getItem('theme')) {
    isDark.value = e.matches
    applyTheme()
  }
}

onMounted(() => {
  const saved = localStorage.getItem('theme')
  isDark.value = saved ? saved !== 'light' : mediaQuery.matches
  applyTheme()
  mediaQuery.addEventListener('change', onSystemChange)
})

onUnmounted(() => { mediaQuery.removeEventListener('change', onSystemChange) })

function downloadScript() {
  const a = document.createElement('a')
  a.href = import.meta.env.BASE_URL + 'Invoke-WindowsOptimization.ps1'
  a.download = 'Invoke-WindowsOptimization.ps1'
  a.click()
}

function toggleTheme() {
  isDark.value = !isDark.value
  applyTheme()
  localStorage.setItem('theme', isDark.value ? 'dark' : 'light')
}
</script>

<style scoped>
.navbar { height: 48px; flex-shrink: 0; background: var(--nav-bg); display: flex; align-items: center; }
.nav-brand { width: var(--sidebar-w, 360px); flex-shrink: 0; display: flex; align-items: center; gap: 8px; padding: 0 12px; border-right: 1px solid var(--nav-divider); height: 100%; }
.nav-logo-img { width: 28px; height: 28px; object-fit: contain; }
.nav-title { font-size: 14px; font-weight: 700; color: var(--nav-text); white-space: nowrap; }
.nav-actions { display: flex; align-items: center; gap: 4px; flex: 1; padding: 0 12px; }
.nav-spacer { flex: 1; }
.nav-btn { display: flex; align-items: center; padding: 6px 12px; border-radius: 5px; border: 1px solid var(--nav-btn-border); background: var(--nav-btn-bg); color: var(--nav-text); font-size: 11px; font-family: 'Montserrat', sans-serif; font-weight: 500; cursor: pointer; white-space: nowrap; }
.nav-btn:hover { background: var(--nav-btn-hover); }
.nav-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.nav-btn.download { background: var(--nav-accent-bg); border-color: var(--nav-accent-bdr); color: var(--nav-accent-txt); font-weight: 600; }
.nav-div { width: 1px; height: 22px; background: var(--nav-divider); margin: 0 4px; }
.nav-filename { font-size: 11px; color: rgba(255,255,255,0.4); margin: 0 6px; }
.nav-modified { display: flex; align-items: center; gap: 4px; font-size: 10px; font-weight: 600; color: #fbbf24; }
.mod-dot { width: 5px; height: 5px; border-radius: 50%; background: #fbbf24; }
.theme-toggle { padding: 5px 11px; border-radius: 20px; border: 1px solid var(--nav-btn-border); background: var(--nav-btn-bg); color: var(--nav-text); font-size: 11px; font-family: 'Montserrat', sans-serif; font-weight: 600; cursor: pointer; margin-left: 4px; }
.nav-hamburger { display: none; }
@media (max-width: 768px) { .nav-hamburger { display: flex; } }
</style>
