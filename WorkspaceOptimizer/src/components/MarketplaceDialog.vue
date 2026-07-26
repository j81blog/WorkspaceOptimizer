<template>
  <!-- Fixed height (2:3 of the width) so the dialog does not resize as the catalog
       loads or as filters narrow the list. -->
  <BaseDialog :visible="visible" title="Marketplace" width="960px" height="640px" :scroll-body="false"
    @update:visible="emit('update:visible', $event)">

    <div class="mk-body">
      <!-- Left: browse -->
      <div class="mk-list">
        <div class="mk-filters">
          <input v-model="search" class="mk-search" placeholder="Search catalog…" />
          <div class="mk-kinds">
            <button v-for="k in KINDS" :key="k.value" class="dlg-btn small"
              :class="{ primary: kind === k.value }" @click="kind = k.value">{{ k.label }}</button>
          </div>
        </div>

        <!-- One bad catalog must not hide the ones that loaded. -->
        <div v-if="failed.length && !loading" class="mk-partial">
          <div class="mk-partial-hdr">
            {{ failed.length }} of {{ catalog?.results.length }} catalogs failed to load
          </div>
          <div v-for="f in failed" :key="f.url" class="mk-partial-row">
            <span class="mono">{{ originLabel(f.url) }}</span>: {{ f.error }}
          </div>
        </div>

        <div v-if="loading" class="mk-status">Loading catalog…</div>
        <div v-else-if="allFailed" class="mk-status mk-status--error">
          <div>No catalog could be loaded.</div>
          <button class="dlg-btn small" @click="load(true)">Retry</button>
        </div>
        <div v-else-if="noCatalogsConfigured" class="mk-status">
          <div>No catalog is configured.</div>
          <div class="mk-status-hint">
            <span class="mono">VITE_MARKETPLACE_DISABLE_BUNDLED</span> is set but no
            <span class="mono">VITE_MARKETPLACE_URL</span> was given, so there is nothing to
            load. Set a catalog URL, or turn the Marketplace off entirely with
            <span class="mono">VITE_DISABLE_MARKETPLACE</span>.
          </div>
        </div>
        <div v-else-if="!catalog?.entries.length" class="mk-status">
          <div>This catalog is empty.</div>
          <div class="mk-status-hint">No templates or snippets have been published yet.</div>
          <a v-if="brand.repoUrl" class="mk-status-link" :href="brand.repoUrl"
            target="_blank" rel="noopener noreferrer">Contribute one on {{ repoHost }} ↗</a>
        </div>
        <div v-else-if="!filtered.length" class="mk-status">No entries match your search.</div>

        <div v-else class="mk-items">
          <div v-for="e in filtered" :key="e.uid" class="mk-item" :class="{ active: selectedUid === e.uid }"
            @click="selectedUid = e.uid">
            <div class="mk-item-top">
              <span class="mk-item-name">{{ e.name }}</span>
              <span class="mk-kind" :class="'mk-kind--' + e.kind">{{ e.kind }}</span>
            </div>
            <div v-if="e.description" class="mk-item-desc">{{ e.description }}</div>
            <div class="mk-item-meta">
              <span v-if="e.version" class="mono">v{{ e.version }}</span>
              <span v-if="e.itemCount !== null">{{ e.itemCount }} items</span>
              <span v-if="e.category">{{ e.category }}</span>
              <span v-if="multipleCatalogs" class="mk-item-src">{{ e.catalogName }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Right: detail -->
      <div v-if="selected" class="mk-detail">
        <div class="mk-detail-name">{{ selected.name }}</div>
        <div class="mk-detail-sub">
          <span class="mk-kind" :class="'mk-kind--' + selected.kind">{{ selected.kind }}</span>
          <span v-if="selected.version" class="mono">v{{ selected.version }}</span>
          <span v-if="selected.author">by {{ selected.author }}</span>
        </div>
        <p v-if="selected.description" class="mk-detail-desc">{{ selected.description }}</p>

        <div v-if="selected.tags.length" class="mk-tags">
          <span v-for="t in selected.tags" :key="t" class="mk-tag">{{ t }}</span>
        </div>

        <div class="mk-detail-facts">
          <div v-if="selected.itemCount !== null"><span class="mk-lbl">Items</span> {{ selected.itemCount }}</div>
          <div v-if="selected.category"><span class="mk-lbl">Category</span> {{ selected.category }}</div>
          <div v-if="multipleCatalogs"><span class="mk-lbl">Catalog</span> {{ selected.catalogName }}</div>
          <div><span class="mk-lbl">Source</span> <span class="mono mk-url">{{ resolvedUrl }}</span></div>
        </div>

        <div v-if="trusted && !sameOrigin" class="mk-trusted">
          <strong>{{ originHost }}</strong> is a trusted host for this deployment, so no
          confirmation is required before importing.
        </div>
        <div v-else-if="!trusted" class="mk-external">
          External source: <strong>{{ originHost }}</strong>. You will be asked to confirm before anything is imported.
        </div>

        <p class="mk-detail-note">
          {{ selected.kind === 'template'
            ? 'Loading a template replaces the document currently open in the editor.'
            : 'Snippet items are reviewed before being merged into the current template.' }}
        </p>
      </div>
      <div v-else class="mk-detail mk-detail--empty">Select an entry to see its details.</div>
    </div>

    <template #footer>
      <span v-if="entryError" class="mk-foot-error">{{ entryError }}</span>
      <span v-else-if="catalog?.updated" class="mk-updated">Catalog updated {{ catalog.updated }}</span>
      <span v-else class="mk-updated"></span>
      <button class="dlg-btn" data-tooltip="Re-download the catalog" @click="load(true)">Refresh</button>
      <button class="dlg-btn" @click="emit('update:visible', false)">Cancel</button>
      <button class="dlg-btn primary" :disabled="!selected || busy" @click="onUse">
        {{ busy ? 'Loading…' : (selected?.kind === 'template' ? 'Load Template' : 'Review & Import') }}
      </button>
    </template>
  </BaseDialog>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseDialog from './BaseDialog.vue'
import { brand } from '../branding'
import {
  fetchCatalogs, fetchEntryXml, resolveEntryUrl, isSameOrigin, isTrustedSource, originLabel,
  marketplaceUrls, usingBundledCatalog, noCatalogsConfigured, MarketplaceError,
  type MergedCatalog, type MarketplaceEntry
} from '../core/marketplace'

const KINDS = [
  { value: 'all', label: 'All' },
  { value: 'template', label: 'Templates' },
  { value: 'snippet', label: 'Snippets' }
] as const

const props = defineProps<{ visible: boolean }>()
const emit = defineEmits<{
  'update:visible': [boolean]
  template: [xml: string, entry: MarketplaceEntry, url: string, sameOrigin: boolean]
  snippet: [xml: string, entry: MarketplaceEntry, url: string, sameOrigin: boolean]
}>()

const catalog = ref<MergedCatalog | null>(null)
const loading = ref(false)
const busy = ref(false)
const entryError = ref('')
const search = ref('')
const kind = ref<'all' | 'template' | 'snippet'>('all')
const selectedUid = ref<string | null>(null)

const multipleCatalogs = marketplaceUrls.length > 1
// Host rather than a hardcoded "GitHub", since a fork may be on GitLab or self-hosted.
const repoHost = brand.repoUrl ? originLabel(brand.repoUrl).replace(/^www\./, '') : ''
const failed = computed(() => catalog.value?.results.filter(r => !r.ok) ?? [])
const allFailed = computed(() =>
  !!catalog.value && catalog.value.results.length > 0 && catalog.value.results.every(r => !r.ok)
)

const filtered = computed(() => {
  const entries = catalog.value?.entries ?? []
  const q = search.value.trim().toLowerCase()
  return entries.filter(e => {
    if (kind.value !== 'all' && e.kind !== kind.value) return false
    if (!q) return true
    return e.name.toLowerCase().includes(q)
      || e.description.toLowerCase().includes(q)
      || e.category.toLowerCase().includes(q)
      || e.tags.some(t => t.toLowerCase().includes(q))
  })
})

const selected = computed(() => filtered.value.find(e => e.uid === selectedUid.value) ?? null)

// Entry URLs resolve against the catalog they came from, not the first configured one.
const resolvedUrl = computed(() =>
  selected.value ? resolveEntryUrl(selected.value.url, selected.value.catalogUrl) : ''
)
const sameOrigin = computed(() => !resolvedUrl.value || isSameOrigin(resolvedUrl.value, location.origin))
const trusted = computed(() => !resolvedUrl.value || isTrustedSource(resolvedUrl.value, location.origin))
const originHost = computed(() => originLabel(resolvedUrl.value))

// `immediate` so the catalog also loads when the dialog is mounted already-open,
// rather than only when visible flips false -> true.
watch(() => props.visible, (v) => {
  if (v) load(false)
}, { immediate: true })

// Keep the selection valid as filters narrow the list.
watch(filtered, (list) => {
  if (!list.some(e => e.uid === selectedUid.value)) selectedUid.value = list[0]?.uid ?? null
})

async function load(refresh: boolean) {
  loading.value = true
  entryError.value = ''
  try {
    // fetchCatalogs contains per-catalog failures internally, so a rejection here
    // means something unexpected rather than one bad catalog.
    catalog.value = await fetchCatalogs(undefined, refresh)
    selectedUid.value = filtered.value[0]?.uid ?? null
  } finally {
    loading.value = false
  }
}

async function onUse() {
  const entry = selected.value
  if (!entry) return
  busy.value = true
  entryError.value = ''
  try {
    const xml = await fetchEntryXml(entry)
    // `trusted` covers same-origin and whitelisted hosts alike; the preview uses it
    // to decide whether an acknowledgement is required.
    if (entry.kind === 'template') emit('template', xml, entry, resolvedUrl.value, trusted.value)
    else emit('snippet', xml, entry, resolvedUrl.value, trusted.value)
  } catch (err) {
    entryError.value = err instanceof MarketplaceError
      ? err.message
      : 'Could not load that entry: ' + (err as Error).message
  } finally {
    busy.value = false
  }
}
</script>

<style scoped>
.mk-body { display: flex; flex: 1; min-height: 0; }
.mk-list { width: 380px; flex-shrink: 0; border-right: 1px solid var(--card-border); display: flex; flex-direction: column; min-height: 0; }
.mk-filters { padding: 12px; border-bottom: 1px solid var(--card-border); display: flex; flex-direction: column; gap: 8px; flex-shrink: 0; }
.mk-search {
  height: 32px; background: var(--sb-input-bg); border: 1px solid var(--sb-input-bdr); border-radius: 6px;
  color: var(--sb-input-txt); font-size: 12px; font-family: 'Montserrat', sans-serif; padding: 0 12px;
}
.mk-search:focus { outline: none; border-color: var(--item-bar); }
.mk-kinds { display: flex; gap: 6px; }
.mk-kinds .dlg-btn { flex: 1; }
.mk-status { padding: 24px 16px; font-size: 11px; color: var(--field-label); display: flex; flex-direction: column; gap: 10px; align-items: flex-start; }
.mk-status--error { color: var(--btn-danger-txt); line-height: 1.5; }
.mk-status-hint { font-size: 10.5px; line-height: 1.6; opacity: 0.85; }
.mk-status-link { font-size: 11px; color: var(--item-bar); text-decoration: none; }
.mk-status-link:hover { text-decoration: underline; }
.mk-items { overflow-y: auto; flex: 1; min-height: 0; }
.mk-item { padding: 10px 14px; cursor: pointer; border-bottom: 1px solid var(--sb-border); }
.mk-item:hover { background: var(--item-hover); }
.mk-item.active { background: var(--item-active); border-left: 2px solid var(--item-bar); }
.mk-item-top { display: flex; align-items: center; gap: 8px; }
.mk-item-name { font-size: 12px; font-weight: 600; color: var(--item-name); flex: 1; }
.mk-item-desc { font-size: 10.5px; color: var(--field-label); margin-top: 3px; line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 2; line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.mk-item-meta { display: flex; gap: 10px; font-size: 9.5px; color: var(--field-label); margin-top: 5px; }
.mk-kind { font-size: 9px; font-weight: 700; text-transform: uppercase; padding: 2px 6px; border-radius: 8px; background: var(--sb-input-bg); color: var(--field-label); }
.mk-kind--template { background: #2a2050; color: #b39ddb; }
[data-theme="light"] .mk-kind--template { background: #faf5ff; color: #7c3aed; }
.mk-detail { flex: 1; padding: 18px 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 10px; }
.mk-detail--empty { align-items: center; justify-content: center; color: var(--field-label); font-size: 12px; }
.mk-detail-name { font-size: 15px; font-weight: 700; color: var(--bc-name); }
.mk-detail-sub { display: flex; align-items: center; gap: 10px; font-size: 11px; color: var(--field-label); }
/* pre-line so an author's line breaks survive; long lines still wrap on their own. */
.mk-detail-desc { font-size: 12px; color: var(--field-txt); line-height: 1.6; white-space: pre-line; }
.mk-tags { display: flex; flex-wrap: wrap; gap: 5px; }
.mk-tag { font-size: 9.5px; padding: 2px 7px; border-radius: 9px; background: var(--sb-input-bg); color: var(--field-label); }
.mk-detail-facts { display: flex; flex-direction: column; gap: 5px; font-size: 11px; color: var(--field-txt); border-top: 1px solid var(--card-border); padding-top: 10px; }
.mk-lbl { display: inline-block; min-width: 68px; color: var(--field-label); font-weight: 600; }
.mk-url { word-break: break-all; font-size: 10px; }
.mk-external { font-size: 11px; color: #f59e0b; border: 1px solid #b45309; background: rgba(180, 83, 9, 0.12); border-radius: 6px; padding: 8px 10px; line-height: 1.5; }
.mk-trusted { font-size: 11px; color: #6fcf97; border: 1px solid #2d6a4f; background: rgba(45, 106, 79, 0.12); border-radius: 6px; padding: 8px 10px; line-height: 1.5; }
[data-theme="light"] .mk-trusted { color: #15803d; border-color: #86efac; background: #f0fdf4; }
.mk-partial { padding: 10px 12px; border-bottom: 1px solid var(--card-border); background: rgba(180, 83, 9, 0.10); flex-shrink: 0; }
.mk-partial-hdr { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; color: #f59e0b; margin-bottom: 4px; }
.mk-partial-row { font-size: 10.5px; color: var(--field-label); line-height: 1.5; }
.mk-item-src { margin-left: auto; opacity: 0.75; }
.mk-foot-error { flex: 1; font-size: 10.5px; color: var(--btn-danger-txt); line-height: 1.4; }
.mk-detail-note { font-size: 11px; color: var(--field-label); line-height: 1.5; }
.mk-updated { font-size: 10px; color: var(--field-label); flex: 1; }
</style>
