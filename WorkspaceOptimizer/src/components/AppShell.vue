<template>
  <div class="body-area">
    <div class="sidebar" :class="{ collapsed: collapsed }" :style="{ '--sidebar-w': width + 'px' }">
      <slot name="sidebar" />
    </div>
    <div v-show="!collapsed" class="splitter" @mousedown="startDrag"></div>
    <div class="right-area">
      <slot name="main" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const collapsed = ref(false)
const width = ref(320)

function setSidebarVar(w: number) {
  document.documentElement.style.setProperty('--sidebar-w', w + 'px')
}

onMounted(() => setSidebarVar(width.value))

defineExpose({
  toggleSidebar() { collapsed.value = !collapsed.value }
})

function startDrag(e: MouseEvent) {
  const startX = e.clientX
  const startW = width.value
  document.body.style.userSelect = 'none'
  const onMove = (ev: MouseEvent) => {
    width.value = Math.max(320, Math.min(600, startW + ev.clientX - startX))
    setSidebarVar(width.value)
  }
  const onUp = () => {
    document.body.style.userSelect = ''
    window.removeEventListener('mousemove', onMove)
    window.removeEventListener('mouseup', onUp)
  }
  window.addEventListener('mousemove', onMove)
  window.addEventListener('mouseup', onUp)
}
</script>
