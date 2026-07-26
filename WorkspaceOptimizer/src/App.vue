<template>
  <div class="app-root">
    <div class="main-col">
      <IconRail @new="onNew" @newblank="onNewBlank" @open="onOpen" @save="onSave" @downloadscript="onDownloadScript"
        @manageos="showOsDialog = true" @pdf="onPdf" @about="showAboutDialog = true"
        @marketplace="onOpenMarketplace" @regfile="onRegImport"
        @properties="showProperties = true" />
      <AppShell ref="shell">
        <template #sidebar><ItemList /></template>
        <template #main>
          <div style="display:flex;flex-direction:column;flex:1;overflow:hidden;min-height:0">
            <ItemEditor style="flex:1;overflow:hidden;min-height:0" />
            <ValidationBar @properties="showProperties = true" />
          </div>
        </template>
      </AppShell>
    </div>
    <input ref="fileInput" type="file" accept=".xml" style="display:none" @change="onFileSelected" />
    <PropertiesDialog v-model:visible="showProperties" />
    <OSDialog v-model:visible="showOsDialog" />
    <PdfDialog v-model:visible="showPdfDialog" />
    <AboutDialog v-model:visible="showAboutDialog" />
    <MarketplaceDialog v-model:visible="showMarketplace"
      @template="onMarketplaceTemplate" @snippet="onMarketplaceSnippet" />
    <RegImportDialog v-model:visible="showRegImport" @confirm="onRegConfirm" />
    <MergePreviewDialog v-model:visible="showMergePreview" :plan="mergePlan" :source="mergeSource"
      @confirm="onMergeConfirm" />
    <DownloadWarningDialog v-model:visible="showDownloadWarning" @confirm="onDownloadConfirmed" />
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import IconRail from './components/IconRail.vue'
import AppShell from './components/AppShell.vue'
import ItemList from './components/sidebar/ItemList.vue'
import ItemEditor from './components/editor/ItemEditor.vue'
import OSDialog from './components/OSDialog.vue'
import PropertiesDialog from './components/PropertiesDialog.vue'
import PdfDialog from './components/PdfDialog.vue'
import AboutDialog from './components/AboutDialog.vue'
import ValidationBar from './components/ValidationBar.vue'
import MarketplaceDialog from './components/MarketplaceDialog.vue'
import RegImportDialog from './components/RegImportDialog.vue'
import MergePreviewDialog, { type SourceDescriptor } from './components/MergePreviewDialog.vue'
import DownloadWarningDialog from './components/DownloadWarningDialog.vue'
import { documentStore } from './store/document'
import { uiStore } from './store/ui'
import { provenanceStore, nextRegSourceId } from './store/provenance'
import { parseXml } from './core/parser'
import { serializeXml } from './core/serializer'
import { formatVersion } from './core/version'
import { buildMergePlan, applyMergePlan, type MergePlan } from './core/merge'
import {
  originLabel, marketplaceDisabled, regImportDisabled, type MarketplaceEntry
} from './core/marketplace'

const shell = ref<InstanceType<typeof AppShell> | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)
const showOsDialog = ref(false)
const showProperties = ref(false)
const showPdfDialog = ref(false)
const showAboutDialog = ref(false)
const showMarketplace = ref(false)
const showRegImport = ref(false)
const showMergePreview = ref(false)
const showDownloadWarning = ref(false)
const mergePlan = ref<MergePlan | null>(null)
const mergeSource = ref<SourceDescriptor | null>(null)

async function onNew() {
  if (documentStore.dirty && !confirm('Discard unsaved changes?')) return
  try {
    documentStore.load(parseXml(await fetchDefaultXml()), 'Windows.xml')
    uiStore.select(documentStore.document?.items[0]?.id ?? null)
    uiStore.resetFilters()
  } catch { alert('Could not load default template.') }
}

/**
 * Start an empty template: no items, but the OS definitions the app ships with, so the
 * first item added already has somewhere to run. Properties are filled in afterwards.
 */
async function onNewBlank() {
  if (documentStore.dirty && !confirm('Discard unsaved changes?')) return
  try {
    documentStore.newEmpty(parseXml(await fetchDefaultXml()).supportedOs, 'Untitled.xml')
    uiStore.select(null)
    uiStore.resetFilters()
  } catch {
    alert('Could not start a new template: the default OS list failed to load.')
  }
}

function onOpen() { fileInput.value?.click() }

function onFileSelected(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  if (documentStore.dirty && !confirm('Discard unsaved changes?')) return
  const reader = new FileReader()
  reader.onload = () => {
    try {
      documentStore.load(parseXml(reader.result as string), file.name)
      uiStore.select(documentStore.document?.items[0]?.id ?? null)
    } catch (err) { alert('Failed to parse XML: ' + (err as Error).message) }
  }
  reader.readAsText(file)
  ;(e.target as HTMLInputElement).value = ''
}

function onSave() {
  if (!documentStore.document || documentStore.hasErrors) return
  // Imported content deserves a look before it leaves the browser.
  if (provenanceStore.hasImports) { showDownloadWarning.value = true; return }
  doSave()
}

function onDownloadConfirmed() {
  showDownloadWarning.value = false
  doSave()
}

function doSave() {
  if (!documentStore.document) return
  // Stamp a fresh build version only when there are unsaved changes, so downloading
  // an untouched template preserves the version it came with.
  if (documentStore.dirty) {
    const prev = documentStore.document.metadata
    // Spread first so the descriptive fields survive; only the stamp changes.
    documentStore.document.metadata = {
      id: '', name: '', description: '', author: '', category: '', tags: [],
      ...prev,
      version: formatVersion(new Date()),
      schemaVersion: prev?.schemaVersion ?? '1'
    }
  }
  const blob = new Blob([serializeXml(documentStore.document)], { type: 'application/xml' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = documentStore.filename
  a.click()
  URL.revokeObjectURL(a.href)
  documentStore.dirty = false
}

function onPdf() { showPdfDialog.value = true }

function onDownloadScript() {
  const a = document.createElement('a')
  a.href = import.meta.env.BASE_URL + 'Invoke-WindowsOptimization.ps1'
  a.download = 'Invoke-WindowsOptimization.ps1'
  a.click()
}

// ── Import plumbing ─────────────────────────────────────────────────────────

async function fetchDefaultXml(): Promise<string> {
  const res = await fetch(import.meta.env.BASE_URL + 'Windows.xml')
  if (!res.ok) throw new Error('Not found')
  return res.text()
}

/**
 * Importing needs somewhere to put the items. A snippet brings its own OS
 * definitions; a .reg file has no OS concept, so borrow the ones the app ships with
 * rather than inventing a list that would drift from Windows.xml.
 */
async function ensureDocument(fallbackOs?: { supportedOs: import('./core/types').OsDefinition[] }): Promise<boolean> {
  if (documentStore.document) return true
  if (fallbackOs?.supportedOs.length) {
    documentStore.newEmpty(fallbackOs.supportedOs, 'Untitled.xml')
    return true
  }
  try {
    documentStore.newEmpty(parseXml(await fetchDefaultXml()).supportedOs, 'Untitled.xml')
    return true
  } catch {
    alert('Could not start a new template: the default OS list failed to load.')
    return false
  }
}

function onMarketplaceTemplate(xml: string, entry: MarketplaceEntry, url: string, sameOrigin: boolean) {
  if (documentStore.dirty && !confirm('Discard unsaved changes?')) return

  let doc
  try {
    doc = parseXml(xml)
  } catch (err) {
    alert('Failed to parse that template: ' + (err as Error).message)
    return
  }

  // A template replaces the document rather than merging, but it is still third-party
  // content that ends up running against a machine, so it gets the same trust gate and
  // the same download warning as a snippet.
  if (!sameOrigin && !confirm(
    `This template comes from ${originLabel(url)}, which is not part of this site.\n\n` +
    'Its items can change registry values, disable services and delete files. ' +
    'Import from this source?'
  )) return

  // Prefer the display name: the id is a slug ("default.template") and makes a poor
  // download filename. Strip characters a filesystem would reject.
  const base = (entry.name || entry.id).replace(/[\\/:*?"<>|]+/g, '').trim() || 'template'
  documentStore.load(doc, `${base}.xml`)
  provenanceStore.record(doc.items.map(i => i.id), {
    id: `mp:${entry.id}`,
    kind: 'marketplace',
    label: entry.name,
    origin: sameOrigin ? '' : originLabel(url)
  })
  uiStore.select(doc.items[0]?.id ?? null)
  uiStore.resetFilters()
  showMarketplace.value = false
}

async function onMarketplaceSnippet(xml: string, entry: MarketplaceEntry, url: string, sameOrigin: boolean) {
  let snippet
  try {
    snippet = parseXml(xml)
  } catch (err) {
    alert('Failed to parse that snippet: ' + (err as Error).message)
    return
  }
  if (!await ensureDocument(snippet)) return

  mergePlan.value = buildMergePlan(documentStore.document!, snippet.items, snippet.supportedOs)
  mergeSource.value = {
    id: `mp:${entry.id}`,
    kind: 'marketplace',
    label: entry.name,
    origin: sameOrigin ? '' : originLabel(url),
    sameOrigin,
    originLabel: originLabel(url)
  }
  showMarketplace.value = false
  showMergePreview.value = true
}

// Both routes re-check their flag here as well as hiding the menu entry, so a
// disabled feature cannot be reached even if something else triggers the event.
function onOpenMarketplace() {
  if (marketplaceDisabled) return
  showMarketplace.value = true
}

async function onRegImport() {
  if (regImportDisabled) return
  if (!await ensureDocument()) return
  showRegImport.value = true
}

function onRegConfirm(plan: MergePlan, filename: string) {
  mergePlan.value = plan
  mergeSource.value = {
    id: nextRegSourceId(filename),
    kind: 'reg',
    label: filename,
    origin: '',
    sameOrigin: true,          // a file the user picked from their own disk
    originLabel: filename
  }
  showRegImport.value = false
  applyMerge()
}

/** Shared confirm path for both snippet and .reg imports. */
function onMergeConfirm() {
  showMergePreview.value = false
  applyMerge()
}

function applyMerge() {
  const plan = mergePlan.value
  const source = mergeSource.value
  if (!plan || !source || !documentStore.document) return

  const { items, osToAdd } = applyMergePlan(plan, documentStore.document)
  if (!items.length) return

  for (const os of osToAdd) documentStore.addOsDefinition(os)
  documentStore.addItems(items)
  provenanceStore.record(items.map(i => i.id), {
    id: source.id, kind: source.kind, label: source.label, origin: source.origin
  })

  // Select the first imported item so it is visible, but leave the filters alone:
  // narrowing to its category hides the rest of the template and makes the sidebar
  // count read as though everything else had vanished.
  uiStore.resetFilters()
  uiStore.select(items[0].id)

  mergePlan.value = null
  mergeSource.value = null
}

onMounted(() => { window.addEventListener('beforeunload', e => { if (documentStore.dirty) e.preventDefault() }) })
</script>
