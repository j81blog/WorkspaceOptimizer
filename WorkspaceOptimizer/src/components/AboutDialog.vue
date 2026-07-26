<template>
  <BaseDialog :visible="visible" :title="`About ${brand.name}`" width="520px"
    @update:visible="emit('update:visible', $event)">

    <div class="about-body">
      <img :src="brand.logo" class="about-logo" :alt="brand.name + ' logo'" @error="onLogoError" />
      <div class="about-info">
        <div class="about-meta">Last updated: {{ lastUpdated }}</div>
        <div class="about-versions">
          <div class="about-versions-label">Versions:</div>
          <div class="about-versions-grid">
            <span>Script</span><span>: {{ scriptVersion }}</span>
            <span>XML</span><span>: {{ xmlVersion }}</span>
          </div>
        </div>
        <button class="about-link about-whatsnew" data-tooltip="Recent changes" @click="showWhatsNew = true">
          What's New →
        </button>

        <!-- Fork's own vendor + link, layered ABOVE the permanent original credit -->
        <div v-if="brand.vendor" class="about-author">Distributed by <strong>{{ brand.vendor }}</strong></div>
        <a v-if="brand.url" class="about-link" :href="brand.url" target="_blank" rel="noopener noreferrer">{{ brandUrlLabel() }} ↗</a>

        <!-- Permanent original author credit, always shown, not configurable -->
        <div class="about-author">Created by <strong>{{ ORIGINAL_CREDIT }}</strong></div>
        <a class="about-link" href="https://blog.j81.nl" target="_blank" rel="noopener noreferrer">blog.j81.nl ↗</a>

        <div class="about-divider"></div>
        <div class="about-desc">{{ brand.description }}</div>
        <div v-if="isRebranded" class="about-powered">
          Powered by <a class="about-link-inline" href="https://workspaceoptimizer.j81.nl/" target="_blank" rel="noopener noreferrer">Workspace Optimizer</a>
        </div>
      </div>
    </div>

    <template #footer>
      <button class="dlg-btn primary" data-tooltip="Close this dialog" @click="close">Close</button>
    </template>
  </BaseDialog>
  <WhatsNewDialog v-model:visible="showWhatsNew" />
</template>

<script setup lang="ts">
import { ref } from 'vue'
import BaseDialog from './BaseDialog.vue'
import { brand, onLogoError, brandUrlLabel, ORIGINAL_CREDIT, isRebranded } from '../branding'
import WhatsNewDialog from './WhatsNewDialog.vue'

defineProps<{ visible: boolean }>()
const emit = defineEmits<{ 'update:visible': [boolean] }>()

const showWhatsNew = ref(false)

const lastUpdated = __BUILD_DATE__
const scriptVersion = __SCRIPT_VERSION__
const xmlVersion = __XML_VERSION__

function close() {
  emit('update:visible', false)
}

// Escape is handled by BaseDialog, which claims the event so the nested What's New
// dialog closes first when both are open.
</script>

<style scoped>
/* Backdrop, header, footer and .dlg-btn come from BaseDialog and style.css. */
.about-body { display: flex; gap: 24px; align-items: flex-start; padding: 20px; }
.about-logo { width: 52px; height: 52px; object-fit: contain; flex-shrink: 0; margin-top: 2px; }
.about-info { display: flex; flex-direction: column; gap: 6px; flex: 1; }
.about-meta { font-size: 11px; color: var(--field-label); }
.about-versions { font-size: 11px; color: var(--field-label); }
.about-versions-label { font-weight: 600; margin-bottom: 2px; }
.about-versions-grid { display: grid; grid-template-columns: max-content 1fr; column-gap: 8px; row-gap: 1px; padding-left: 8px; }
.about-author { font-size: 12px; color: var(--field-txt); }
.about-link { font-size: 11px; color: var(--item-bar); text-decoration: none; }
.about-link:hover { text-decoration: underline; }
.about-whatsnew { background: none; border: none; padding: 0; cursor: pointer; text-align: left; font-family: 'Montserrat', sans-serif; font-weight: 600; align-self: flex-start; }
.about-divider { border-top: 1px solid var(--card-border); margin: 6px 0; }
.about-desc { font-size: 11px; color: var(--field-label); line-height: 1.5; }
.about-powered { font-size: 10px; color: var(--field-label); margin-top: 6px; }
.about-link-inline { color: var(--item-bar); text-decoration: none; }
.about-link-inline:hover { text-decoration: underline; }
</style>
