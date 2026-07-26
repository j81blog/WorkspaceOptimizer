<template>
  <header class="toolbar">
    <!-- Brand block: occupies the sidebar width so action buttons align with the editor pane -->
    <div class="tb-brand">
      <div class="tb-logo-box">
        <img :src="brand.logo" class="tb-logo" :alt="brand.name" @error="onLogoError" />
      </div>
      <span class="tb-brand-name">{{ brand.name }}</span>
    </div>

    <!-- Everything here is also in Options, which is the single place a new user can
         find every template action without scanning the toolbar. -->
    <OptionsMenu
      @new="emit('newblank')" @default="emit('new')" @open="emit('open')"
      @marketplace="emit('marketplace')" @regfile="emit('regfile')"
      @manageos="emit('manageos')" @pdf="emit('pdf')" />

    <div class="tb-divider"></div>

    <button class="tb-btn" data-tooltip="Create a new template from built-in defaults" @click="emit('new')">
      New from Default
    </button>
    <button class="tb-btn" data-tooltip="Open an existing XML template file" @click="emit('open')">
      Open Template
    </button>

    <div class="tb-divider"></div>

    <button
      class="tb-btn tb-btn--accent"
      :class="{ 'tb-btn--disabled': !canDownloadXml }"
      data-tooltip="Download the template as an XML file"
      @click="canDownloadXml && emit('save')"
    >
      Download XML
    </button>
    <button
      class="tb-btn tb-btn--accent"
      data-tooltip="Download the PowerShell deployment script"
      @click="emit('downloadscript')"
    >
      Download Script
    </button>

    <div class="tb-divider"></div>

    <button
      class="tb-btn"
      :class="{ 'tb-btn--alert': missingMeta.length > 0 }"
      :data-tooltip="missingMeta.length
        ? `${missingMeta.join(', ')} ${missingMeta.length === 1 ? 'is' : 'are'} required before download`
        : 'Edit the template name, description, author and tags'"
      @click="emit('properties')"
    >
      Properties
    </button>
    <!-- Manage OS and PDF Report live in Options only: both are occasional actions, and
         the toolbar was long enough to make the frequent ones hard to find. -->

    <!-- Spacer -->
    <div class="tb-spacer"></div>

    <!-- File name + Modified indicator -->
    <span v-if="documentStore.filename" class="tb-filename mono">{{ documentStore.filename }}</span>
    <span v-if="documentStore.dirty" class="tb-modified"><span class="tb-mod-dot"></span>Modified</span>

    <!-- About -->
    <button class="tb-btn" data-tooltip="About this application" @click="emit('about')">
      About
    </button>

    <!-- Theme toggle -->
    <button
      class="tb-icon-btn"
      :class="{ 'tb-icon-btn--accent': true }"
      :data-tooltip="isDark ? 'Switch to light theme' : 'Switch to dark theme'"
      @click="toggleTheme"
    >
      <svg v-if="isDark" viewBox="0 0 24 24"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>
      <svg v-else viewBox="0 0 24 24"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
    </button>
  </header>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { documentStore } from '../store/document'
import { brand, onLogoError } from '../branding'
import OptionsMenu from './OptionsMenu.vue'

const emit = defineEmits<{
  new: []; newblank: []; open: []; save: []; downloadscript: []; manageos: []; pdf: []
  about: []; marketplace: []; regfile: []; properties: []
}>()

/**
 * Required template properties that are still empty. Drives the alert styling, so the
 * colour only appears when there is something to fix. Empty when no document is open.
 */
const missingMeta = computed(() => {
  const doc = documentStore.document
  if (!doc) return []
  const m = doc.metadata
  const out: string[] = []
  if (!m?.name?.trim()) out.push('Name')
  if (!m?.description?.trim()) out.push('Description')
  if (!m?.author?.trim()) out.push('Author')
  return out
})

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
.toolbar {
  height: 56px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 0 14px;
  background: var(--bc-bg);
  border-bottom: 1px solid var(--card-border);
  z-index: 10;
  position: relative;
}

/* Brand block: fixed to the sidebar width so the action buttons line up with the editor pane.
   width = sidebar load/min width (320px) minus this toolbar's left padding (14px). */
.tb-brand {
  width: calc(320px - 14px);
  flex-shrink: 0;
  display: flex;
  align-items: center;
  gap: 10px;
  overflow: hidden;
}

/* Logo box: fixed height, width grows to the logo's natural aspect ratio */
.tb-logo-box {
  height: 40px;
  width: auto;
  max-width: 160px;
  flex-shrink: 0;
  border: 1px dashed var(--field-border);
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  padding: 3px;
}
.tb-logo {
  height: 100%;
  width: auto;
  object-fit: contain;
}

/* App title */
.tb-brand-name {
  font-size: 14px;
  font-weight: 700;
  color: var(--bc-name);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Divider */
.tb-divider {
  width: 1px;
  height: 20px;
  background: var(--card-border);
  flex-shrink: 0;
  margin: 0 2px;
}

/* Spacer */
.tb-spacer {
  flex: 1;
}

/* Labeled action buttons */
.tb-btn {
  height: 28px;
  padding: 0 11px;
  border-radius: 6px;
  font-size: 11.5px;
  font-weight: 600;
  font-family: inherit;
  white-space: nowrap;
  flex-shrink: 0;
  cursor: pointer;
  border: 1px solid var(--sb-btn-bdr);
  background: var(--sb-btn-bg);
  color: var(--sb-btn-txt);
  transition: background 0.15s, border-color 0.15s, color 0.15s;
}
.tb-btn:hover {
  background: var(--sb-btn-hover-bg);
  border-color: var(--sb-btn-hover-bdr);
}
/* Only shown while a required property is missing, so the colour carries meaning. */
.tb-btn--alert {
  color: var(--btn-danger-txt);
  border-color: var(--btn-danger-bdr);
  background: var(--btn-danger-bg);
  font-weight: 700;
}
.tb-btn--alert:hover {
  background: var(--btn-danger-bg);
  border-color: var(--btn-danger-txt);
}
.tb-btn--accent {
  background: var(--btn-primary-bg);
  border-color: var(--btn-primary-bdr);
  color: var(--btn-primary-txt);
}
.tb-btn--accent:hover {
  filter: brightness(1.1);
}
.tb-btn--disabled {
  opacity: 0.35;
  cursor: not-allowed;
}
.tb-btn--disabled:hover {
  background: var(--sb-btn-bg);
  border-color: var(--sb-btn-bdr);
  filter: none;
}
.tb-btn--accent.tb-btn--disabled:hover {
  background: var(--btn-primary-bg);
  border-color: var(--btn-primary-bdr);
  filter: none;
}

/* Icon-only square buttons (hamburger, theme) */
.tb-icon-btn {
  width: 28px;
  height: 28px;
  padding: 0;
  border-radius: 6px;
  flex-shrink: 0;
  cursor: pointer;
  border: 1px solid var(--sb-btn-bdr);
  background: var(--sb-btn-bg);
  color: var(--sb-btn-txt);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.15s, border-color 0.15s, color 0.15s;
}
.tb-icon-btn:hover {
  background: var(--sb-btn-hover-bg);
  border-color: var(--sb-btn-hover-bdr);
}
.tb-icon-btn--accent {
  background: var(--btn-primary-bg);
  border-color: var(--btn-primary-bdr);
  color: var(--btn-primary-txt);
}
.tb-icon-btn--accent:hover {
  filter: brightness(1.1);
}
.tb-icon-btn svg {
  width: 14px;
  height: 14px;
  fill: none;
  stroke: currentColor;
  stroke-width: 2;
  stroke-linecap: round;
  stroke-linejoin: round;
}

/* Filename + Modified */
.tb-filename {
  font-size: 11px;
  color: var(--as-txt);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 200px;
  flex-shrink: 1;
}
.tb-modified {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
  font-weight: 600;
  color: #fbbf24;
  white-space: nowrap;
  flex-shrink: 0;
}
.tb-mod-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #fbbf24;
  flex-shrink: 0;
}
</style>
