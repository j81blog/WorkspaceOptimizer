import { createApp } from 'vue'
import { initTooltips } from './tooltip'
import { applyBranding } from './branding'
import PrimeVue from 'primevue/config'
import Aura from '@primeuix/themes/aura'
import 'primeicons/primeicons.css'
import App from './App.vue'
import './style.css'

applyBranding()

const app = createApp(App)
app.use(PrimeVue, {
  theme: {
    preset: Aura,
    options: {
      darkModeSelector: '[data-theme="dark"]',
      cssLayer: false
    }
  }
})
app.mount('#app')
initTooltips()
