<template>
  <div class="app-root">
    <div class="main-col">
      <IconRail @new="onNew" @open="onOpen" @save="onSave" @downloadscript="onDownloadScript"
        @manageos="showOsDialog = true" @pdf="onPdf" @about="showAboutDialog = true" />
      <AppShell ref="shell">
        <template #sidebar><ItemList /></template>
        <template #main>
          <div style="display:flex;flex-direction:column;flex:1;overflow:hidden;min-height:0">
            <ItemEditor style="flex:1;overflow:hidden;min-height:0" />
            <ValidationBar />
          </div>
        </template>
      </AppShell>
    </div>
    <input ref="fileInput" type="file" accept=".xml" style="display:none" @change="onFileSelected" />
    <OSDialog v-model:visible="showOsDialog" />
    <PdfDialog v-model:visible="showPdfDialog" />
    <AboutDialog v-model:visible="showAboutDialog" />
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import IconRail from './components/IconRail.vue'
import AppShell from './components/AppShell.vue'
import ItemList from './components/sidebar/ItemList.vue'
import ItemEditor from './components/editor/ItemEditor.vue'
import OSDialog from './components/OSDialog.vue'
import PdfDialog from './components/PdfDialog.vue'
import AboutDialog from './components/AboutDialog.vue'
import ValidationBar from './components/ValidationBar.vue'
import { documentStore } from './store/document'
import { uiStore } from './store/ui'
import { parseXml } from './core/parser'
import { serializeXml } from './core/serializer'

const shell = ref<InstanceType<typeof AppShell> | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)
const showOsDialog = ref(false)
const showPdfDialog = ref(false)
const showAboutDialog = ref(false)

async function onNew() {
  if (documentStore.dirty && !confirm('Discard unsaved changes?')) return
  try {
    const res = await fetch('Windows.xml')
    if (!res.ok) throw new Error('Not found')
    documentStore.load(parseXml(await res.text()), 'Windows.xml')
    uiStore.select(documentStore.document?.items[0]?.id ?? null)
    uiStore.resetFilters()
  } catch { alert('Could not load default template.') }
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

onMounted(() => { window.addEventListener('beforeunload', e => { if (documentStore.dirty) e.preventDefault() }) })
</script>
