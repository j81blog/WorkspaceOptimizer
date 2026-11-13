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

// Build only: the dev server relies on inline scripts for HMR. Styles stay inline-allowed
// because PrimeVue and CodeMirror inject <style> tags at runtime. https: in img-src and
// connect-src covers a fork's logo URL and catalogs hosted anywhere.
const CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: https:",
  "font-src 'self'",
  "connect-src 'self' https:",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'none'",
].join('; ')

const cspPlugin = {
  name: 'csp-meta',
  apply: 'build' as const,
  transformIndexHtml: () => [
    { tag: 'meta', attrs: { 'http-equiv': 'Content-Security-Policy', content: CSP }, injectTo: 'head' as const },
  ],
}

export default defineConfig({
  plugins: [vue(), cspPlugin],
  base: process.env.VITE_BASE_URL ?? '/',
  define: {
    __BUILD_DATE__: JSON.stringify(new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })),
    __SCRIPT_VERSION__: JSON.stringify(readScriptVersion()),
    __XML_VERSION__: JSON.stringify(readXmlVersion()),
  },
  // CHANGELOG.md lives at the repo root, one level above this app, and is imported
  // with ?raw by the What's New dialog. Both the dev server and Vitest need to be
  // told that reading outside the project root is intentional here.
  server: {
    fs: { allow: ['..'] }
  },
  test: {
    environment: 'jsdom',
    globals: true,
    server: {
      deps: { fsAllow: ['..'] }
    }
  }
})
