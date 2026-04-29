import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import fs from 'fs'
import path from 'path'

function readScriptVersion(): string {
  const ps1 = fs.readFileSync(path.resolve(__dirname, 'public/Invoke-WindowsOptimization.ps1'), 'utf-8')
  const m = ps1.match(/\$script:ScriptVersion\s*=\s*'([^']+)'/)
  return m?.[1] ?? 'unknown'
}

function readXmlVersion(): string {
  const xml = fs.readFileSync(path.resolve(__dirname, 'public/Windows.xml'), 'utf-8')
  const m = xml.match(/<Version>([^<]+)<\/Version>/)
  return m?.[1] ?? 'unknown'
}

export default defineConfig({
  plugins: [vue()],
  base: process.env.VITE_BASE_URL ?? '/',
  define: {
    __BUILD_DATE__: JSON.stringify(new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })),
    __SCRIPT_VERSION__: JSON.stringify(readScriptVersion()),
    __XML_VERSION__: JSON.stringify(readXmlVersion()),
  },
  test: {
    environment: 'jsdom',
    globals: true
  }
})
