<template>
  <div ref="root" class="om">
    <!-- The tooltip is dropped while open, otherwise it covers the first menu entry. -->
    <button class="om-trigger" :class="{ open }"
      :data-tooltip="open ? undefined : 'Template actions and imports'"
      @click="toggle">
      Options <span class="om-caret">▾</span>
    </button>

    <div v-if="open" class="om-menu">
      <button class="om-item" @click="pick('new')">
        New template
        <span class="om-sub">Start empty and build from scratch</span>
      </button>
      <button class="om-item" @click="pick('default')">
        New from default
        <span class="om-sub">Load the built-in template</span>
      </button>
      <button class="om-item" @click="pick('open')">
        Open template…
        <span class="om-sub">Load an XML file from disk</span>
      </button>

      <div v-if="importsAvailable" class="om-sep"></div>

      <!-- Import routes as a submenu: they add to a template rather than replacing it. -->
      <div v-if="importsAvailable" class="om-sub-wrap"
        @mouseenter="submenu = true" @mouseleave="submenu = false">
        <button class="om-item om-item--parent" @click="submenu = !submenu">
          <span class="om-parent-row">
            Add from…
            <span class="om-arrow">▸</span>
          </span>
          <span class="om-sub">Marketplace or a .reg file</span>
        </button>
        <div v-if="submenu" class="om-menu om-submenu">
          <button v-if="!marketplaceDisabled" class="om-item" @click="pick('marketplace')">
            Marketplace
            <span class="om-sub">Templates and snippets</span>
          </button>
          <button v-if="!regImportDisabled" class="om-item" @click="pick('regfile')">
            Import .reg file
            <span class="om-sub">Registry values from a file</span>
          </button>
        </div>
      </div>

      <div class="om-sep"></div>

      <button class="om-item" :disabled="!hasDocument" @click="pick('manageos')">
        Manage OS
        <span class="om-sub">Add, edit or remove OS definitions</span>
      </button>
      <button class="om-item" :disabled="!canPdf" @click="pick('pdf')">
        PDF report
        <span class="om-sub">Export an overview of all items</span>
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { hideTooltip } from '../tooltip'
import { documentStore } from '../store/document'
import { marketplaceDisabled, regImportDisabled } from '../core/marketplace'

type Action = 'new' | 'default' | 'open' | 'marketplace' | 'regfile' | 'manageos' | 'pdf'

const emit = defineEmits<{
  new: []; default: []; open: []
  marketplace: []; regfile: []
  manageos: []; pdf: []
}>()

const root = ref<HTMLElement | null>(null)
const open = ref(false)
const submenu = ref(false)

const importsAvailable = !marketplaceDisabled || !regImportDisabled
const hasDocument = computed(() => !!documentStore.document)
const canPdf = computed(() =>
  !!documentStore.document?.items.length && !!documentStore.document?.supportedOs.length)

function toggle() {
  open.value = !open.value
  submenu.value = false
  // The pointer stays on the trigger, so no mouseout fires to clear the tooltip
  // that would otherwise sit on top of the first menu entry.
  if (open.value) hideTooltip()
}

function close() {
  open.value = false
  submenu.value = false
}

function pick(what: Action) {
  if (what === 'manageos' && !hasDocument.value) return
  if (what === 'pdf' && !canPdf.value) return
  close()
  switch (what) {
    case 'new': emit('new'); break
    case 'default': emit('default'); break
    case 'open': emit('open'); break
    case 'marketplace': emit('marketplace'); break
    case 'regfile': emit('regfile'); break
    case 'manageos': emit('manageos'); break
    case 'pdf': emit('pdf'); break
  }
}

function onDocMouseDown(e: MouseEvent) {
  if (open.value && root.value && !root.value.contains(e.target as Node)) close()
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') close()
}

onMounted(() => {
  document.addEventListener('mousedown', onDocMouseDown)
  document.addEventListener('keydown', onKeydown)
})
onUnmounted(() => {
  document.removeEventListener('mousedown', onDocMouseDown)
  document.removeEventListener('keydown', onKeydown)
})
</script>

<style scoped>
.om { position: relative; display: flex; flex-shrink: 0; }
/* Matches .tb-btn in IconRail, which is scoped there and so cannot be reused here. */
.om-trigger {
  height: 28px; padding: 0 11px; border-radius: 6px;
  border: 1px solid var(--sb-btn-bdr); background: var(--sb-btn-bg); color: var(--sb-btn-txt);
  font-size: 11.5px; font-family: inherit; font-weight: 600; white-space: nowrap; cursor: pointer;
  display: flex; align-items: center; gap: 6px;
  transition: background 0.15s, border-color 0.15s, color 0.15s;
}
.om-trigger:hover { background: var(--sb-btn-hover-bg); border-color: var(--sb-btn-hover-bdr); }
.om-trigger.open { border-color: var(--item-bar); color: var(--item-bar); }
.om-caret { font-size: 8px; }
.om-menu {
  position: absolute; top: calc(100% + 6px); left: 0; z-index: 50;
  min-width: 260px;
  background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 6px;
  box-shadow: 0 12px 32px rgba(0,0,0,0.35); overflow: visible; padding: 4px 0;
}
.om-item {
  display: flex; flex-direction: column; gap: 2px; width: 100%; text-align: left;
  padding: 8px 12px; background: none; border: none; cursor: pointer;
  color: var(--item-name); font-family: 'Montserrat', sans-serif; font-size: 12px; font-weight: 600;
}
.om-item:hover:not(:disabled) { background: var(--item-hover); }
.om-item:disabled { opacity: 0.4; cursor: not-allowed; }
.om-sub { font-size: 10px; font-weight: 400; color: var(--field-label); }
.om-sep { height: 1px; background: var(--sb-border); margin: 4px 0; }
.om-sub-wrap { position: relative; }
.om-parent-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.om-arrow { font-size: 9px; color: var(--field-label); }
/* -5px overlaps the parent's padding so the pointer does not cross a gap and close it. */
.om-submenu { top: -5px; left: calc(100% + 2px); min-width: 220px; }
</style>
