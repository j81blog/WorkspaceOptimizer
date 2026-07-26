<template>
  <Teleport to="body">
    <div v-if="visible" class="dialog-backdrop" @click.self="close">
      <div class="dialog" :style="{ width, height }">
        <div class="dlg-header">
          <span class="dlg-title">{{ title }}</span>
          <slot name="header-extra" />
          <button class="dlg-close" data-tooltip="Close" @click="close">×</button>
        </div>

        <div class="dlg-body" :class="{ 'dlg-body--scroll': scrollBody }">
          <slot />
        </div>

        <div v-if="$slots.footer" class="dlg-footer">
          <slot name="footer" />
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { onUnmounted, watch } from 'vue'
import { isEscapeHandled, markEscapeHandled, pushDialog, popDialog, isTopDialog } from '../core/escape'

/**
 * Shared shell for the dialogs added alongside the marketplace work.
 *
 * The existing OSDialog / PdfDialog / AboutDialog keep their own copy-pasted markup
 * for now; migrating them is deliberately left as separate work so this change does
 * not touch dialogs it has no reason to modify. The styling here is lifted verbatim
 * from OSDialog so the two sets stay visually identical.
 */
const props = withDefaults(defineProps<{
  visible: boolean
  title: string
  width?: string
  /** Fixed height. Omit to let the dialog size to its content (capped at 85vh). */
  height?: string
  /** Let the body scroll. Off for dialogs whose body manages its own overflow. */
  scrollBody?: boolean
}>(), {
  width: '780px',
  height: undefined,
  scrollBody: true
})

const emit = defineEmits<{ 'update:visible': [boolean] }>()

function close() {
  emit('update:visible', false)
}

/** Identity for the open-dialog stack, so nesting order is known regardless of
 *  the order listeners happen to be registered in. */
const id = Symbol('dialog')

function onKeydown(e: KeyboardEvent) {
  if (e.key !== 'Escape' || !props.visible) return
  // One Escape closes exactly one dialog: only the topmost acts, and it claims the
  // event so any other listener on `document` skips it.
  if (isEscapeHandled(e) || !isTopDialog(id)) return
  markEscapeHandled(e)
  close()
}

watch(() => props.visible, (v) => {
  if (v) {
    pushDialog(id)
    document.addEventListener('keydown', onKeydown)
  } else {
    popDialog(id)
    document.removeEventListener('keydown', onKeydown)
  }
}, { immediate: true })

onUnmounted(() => {
  popDialog(id)
  document.removeEventListener('keydown', onKeydown)
})
</script>

<style scoped>
.dialog-backdrop { position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; z-index: 1000; }
/* max-height still wins on short viewports, so a fixed height never overflows. */
.dialog { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 10px; max-width: 95vw; max-height: 85vh; display: flex; flex-direction: column; box-shadow: 0 20px 60px rgba(0,0,0,0.4); }
.dlg-header { display: flex; align-items: center; gap: 12px; padding: 14px 20px; border-bottom: 1px solid var(--card-border); }
.dlg-title { font-size: 14px; font-weight: 700; color: var(--bc-name); flex: 1; }
.dlg-close { background: none; border: none; color: var(--field-label); font-size: 20px; cursor: pointer; line-height: 1; }
.dlg-body { display: flex; flex-direction: column; flex: 1; min-height: 0; }
.dlg-body--scroll { overflow-y: auto; }
.dlg-footer { display: flex; align-items: center; justify-content: flex-end; gap: 10px; padding: 14px 20px; border-top: 1px solid var(--card-border); }
</style>
