<template>
  <Teleport to="body">
    <div v-if="visible" class="about-backdrop" @click.self="close">
      <div class="about-dialog">
        <button class="about-close" data-tooltip="Close" @click="close">×</button>
        <div class="about-body">
          <img :src="logoUrl" class="about-logo" alt="Workspace Optimizer logo" />
          <div class="about-info">
            <div class="about-title">Workspace Optimizer</div>
            <div class="about-meta">Last updated: {{ lastUpdated }}</div>
            <div class="about-versions">
              <div class="about-versions-label">Versions:</div>
              <div class="about-versions-grid">
                <span>Script</span><span>: {{ scriptVersion }}</span>
                <span>XML</span><span>: {{ xmlVersion }}</span>
              </div>
            </div>
            <div class="about-author">Created by <strong>John Billekens Consultancy & AppVentiX</strong></div>
            <a class="about-link" href="https://appventix.com" target="_blank" rel="noopener noreferrer">appventix.com ↗</a>
            <a class="about-link" href="https://blog.j81.nl" target="_blank" rel="noopener noreferrer">blog.j81.nl ↗</a>
            <div class="about-divider"></div>
            <div class="about-desc">{{ description }}</div>
            <div class="about-footer">
              <button class="about-btn" data-tooltip="Close this dialog" @click="close">Close</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'
import logoUrl from '../assets/WorkspaceOptimizer.png'

defineProps<{ visible: boolean }>()
const emit = defineEmits<{ 'update:visible': [boolean] }>()

const lastUpdated = __BUILD_DATE__
const scriptVersion = __SCRIPT_VERSION__
const xmlVersion = __XML_VERSION__
const description = 'A tool for building and editing Windows cleanup & optimization templates.'

function close() {
  emit('update:visible', false)
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') close()
}

onMounted(() => document.addEventListener('keydown', onKeydown))
onUnmounted(() => document.removeEventListener('keydown', onKeydown))
</script>

<style scoped>
.about-backdrop {
  position: fixed; inset: 0; background: rgba(0,0,0,0.6);
  display: flex; align-items: center; justify-content: center; z-index: 1000;
}
.about-dialog {
  background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 10px;
  padding: 28px 32px; max-width: 520px; width: 95vw;
  box-shadow: 0 20px 60px rgba(0,0,0,0.4); position: relative;
}
.about-close {
  position: absolute; top: 12px; right: 14px;
  background: none; border: none; color: var(--field-label);
  font-size: 20px; cursor: pointer; line-height: 1;
}
.about-body { display: flex; gap: 24px; align-items: flex-start; }
.about-logo { width: 52px; height: 52px; object-fit: contain; flex-shrink: 0; margin-top: 4px; }
.about-info { display: flex; flex-direction: column; gap: 6px; flex: 1; }
.about-title { font-size: 16px; font-weight: 700; color: var(--bc-name); }
.about-meta { font-size: 11px; color: var(--field-label); }
.about-versions { font-size: 11px; color: var(--field-label); }
.about-versions-label { font-weight: 600; margin-bottom: 2px; }
.about-versions-grid { display: grid; grid-template-columns: max-content 1fr; column-gap: 8px; row-gap: 1px; padding-left: 8px; }
.about-author { font-size: 12px; color: var(--field-txt); }
.about-link { font-size: 11px; color: var(--item-bar); text-decoration: none; }
.about-link:hover { text-decoration: underline; }
.about-divider { border-top: 1px solid var(--card-border); margin: 6px 0; }
.about-desc { font-size: 11px; color: var(--field-label); line-height: 1.5; }
.about-footer { display: flex; justify-content: flex-end; margin-top: 8px; }
.about-btn {
  padding: 6px 18px; border-radius: 5px;
  border: 1px solid var(--btn-primary-bdr);
  background: var(--btn-primary-bg); color: var(--btn-primary-txt); font-size: 11px;
  font-family: 'Montserrat', sans-serif; font-weight: 600; cursor: pointer;
}
.about-btn:hover { opacity: 0.85; }
</style>
