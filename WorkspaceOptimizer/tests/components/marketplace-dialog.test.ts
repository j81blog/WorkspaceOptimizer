import { describe, it, expect, afterEach, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
// ?raw rather than fs, matching the rest of the suite: the project types against
// vite/client only, so node's fs types are not available here.
import dialogSource from '../../src/components/MarketplaceDialog.vue?raw'

/**
 * Lives in its own file because marketplaceUrl is read from import.meta.env at module
 * load, so these tests call vi.resetModules(). That would otherwise hand other suites
 * a second copy of shared module state (notably core/escape's WeakSet).
 */

const INDEX = 'https://cdn.example.com/catalog/index.json'

/**
 * fetchCatalogs awaits a Promise.all and then updates state, so one microtask flush
 * is not enough. Flush a few times to let the whole chain settle.
 */
async function settle() {
  for (let i = 0; i < 4; i++) await flushPromises()
}

async function mountWith(entries: unknown[], xml = '<Items></Items>') {
  vi.resetModules()
  vi.stubEnv('VITE_MARKETPLACE_URL', INDEX)
  // Configured catalogs append to the bundled one by default; these tests assert on
  // a single catalog, so keep the bundled one out.
  vi.stubEnv('VITE_MARKETPLACE_DISABLE_BUNDLED', 'true')
  vi.stubGlobal('fetch', vi.fn(async (url: string) =>
    url.endsWith('index.json')
      ? new Response(JSON.stringify({ schemaVersion: 1, entries }), { status: 200 })
      : new Response(xml, { status: 200 })
  ))

  const MarketplaceDialog = (await import('../../src/components/MarketplaceDialog.vue')).default
  const w = mount(MarketplaceDialog, { props: { visible: true }, attachTo: document.body })
  await settle()
  return w
}

/** The primary footer button: "Load Template" or "Review & Import". */
function clickPrimary() {
  const buttons = [...document.querySelectorAll('.dlg-footer .dlg-btn')] as HTMLButtonElement[]
  buttons[buttons.length - 1].click()
}

afterEach(() => {
  document.body.innerHTML = ''
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
  vi.resetModules()
})

/** Open Options and reveal the Add from… submenu, with the given catalog config. */
async function mountMenu(url: string) {
  vi.resetModules()
  vi.stubEnv('VITE_MARKETPLACE_URL', url)
  const OptionsMenu = (await import('../../src/components/OptionsMenu.vue')).default
  const w = mount(OptionsMenu)
  await w.find('.om-trigger').trigger('click')
  await w.find('.om-sub-wrap').trigger('mouseenter')
  return w
}

it('lists both import routes in the submenu, the only place either lives', async () => {
  const w = await mountMenu('https://cdn.example.com/index.json')
  const entries = w.findAll('.om-submenu .om-item')

  expect(entries).toHaveLength(2)
  expect(entries[0].text()).toContain('Marketplace')
  expect(entries[1].text()).toContain('Import .reg file')
  w.unmount()
})

it('offers Marketplace even with no catalog URL configured, via the bundled one', async () => {
  const w = await mountMenu('')
  const marketplace = w.findAll('.om-submenu .om-item')[0]

  expect(marketplace.text()).toContain('Marketplace')
  expect(marketplace.attributes('disabled')).toBeUndefined()

  await marketplace.trigger('click')
  expect(w.emitted('marketplace')).toBeTruthy()
  expect(w.find('.om-menu').exists()).toBe(false)
  w.unmount()
})

async function mountEmpty(repoUrl?: string) {
  vi.resetModules()
  vi.stubEnv('VITE_MARKETPLACE_URL', '')
  if (repoUrl !== undefined) vi.stubEnv('VITE_BRAND_REPO_URL', repoUrl)
  vi.stubGlobal('fetch', vi.fn(async () =>
    new Response(JSON.stringify({ schemaVersion: 1, entries: [] }), { status: 200 })))

  const MarketplaceDialog = (await import('../../src/components/MarketplaceDialog.vue')).default
  const w = mount(MarketplaceDialog, { props: { visible: true }, attachTo: document.body })
  await settle()
  return w
}

it('states an empty catalog in user-facing terms, not configuration terms', async () => {
  const w = await mountEmpty()
  const text = document.body.textContent ?? ''

  expect(text).toContain('This catalog is empty')
  expect(text).toContain('No templates or snippets have been published yet')
  // End users cannot set build variables, so none are mentioned.
  expect(text).not.toContain('VITE_')
  w.unmount()
})

it('links to the source repository by host, not a hardcoded GitHub', async () => {
  const w = await mountEmpty('https://gitlab.example.com/team/wo')
  const link = document.querySelector('.mk-status-link') as HTMLAnchorElement

  expect(link).not.toBeNull()
  expect(link.href).toBe('https://gitlab.example.com/team/wo')
  expect(link.textContent).toContain('gitlab.example.com')
  expect(link.rel).toContain('noopener')
  w.unmount()
})

it('shows no link when the repository is explicitly set to none', async () => {
  const w = await mountEmpty('none')
  expect(document.body.textContent).toContain('This catalog is empty')
  expect(document.querySelector('.mk-status-link')).toBeNull()
  w.unmount()
})

it('explains the misconfiguration when no catalog is left to load', async () => {
  vi.resetModules()
  vi.stubEnv('VITE_MARKETPLACE_URL', '')
  vi.stubEnv('VITE_MARKETPLACE_DISABLE_BUNDLED', 'true')
  const spy = vi.fn()
  vi.stubGlobal('fetch', spy)

  const MarketplaceDialog = (await import('../../src/components/MarketplaceDialog.vue')).default
  const w = mount(MarketplaceDialog, { props: { visible: true }, attachTo: document.body })
  await settle()

  expect(document.body.textContent).toContain('No catalog is configured')
  expect(document.body.textContent).toContain('VITE_DISABLE_MARKETPLACE')
  expect(spy).not.toHaveBeenCalled()          // nothing to fetch
  w.unmount()
})

it('does not offer setup advice when a fork supplies its own empty catalog', async () => {
  const w = await mountWith([])
  expect(document.body.textContent).toContain('This catalog is empty')
  expect(document.body.textContent).not.toContain('VITE_MARKETPLACE_URL')
  w.unmount()
})

describe('feature flags', () => {
  async function mountRail(env: Record<string, string>) {
    vi.resetModules()
    for (const [k, v] of Object.entries(env)) vi.stubEnv(k, v)
    vi.stubGlobal('matchMedia', () => ({
      matches: false, addEventListener() {}, removeEventListener() {}
    }))
    const IconRail = (await import('../../src/components/IconRail.vue')).default
    return mount(IconRail)
  }

  /** Open Options and its Add from… submenu, returning the submenu entries. */
  async function importEntries(w: ReturnType<typeof mount>) {
    await w.find('.om-trigger').trigger('click')
    if (!w.find('.om-sub-wrap').exists()) return []
    await w.find('.om-sub-wrap').trigger('mouseenter')
    return w.findAll('.om-submenu .om-item').map(e => e.text())
  }

  it('hides the Marketplace entry when disabled', async () => {
    const w = await mountRail({ VITE_DISABLE_MARKETPLACE: 'true', VITE_DISABLE_REG_IMPORT: '' })
    const entries = await importEntries(w)

    expect(entries).toHaveLength(1)
    expect(entries[0]).toContain('Import .reg file')
    w.unmount()
  })

  it('hides the .reg entry when disabled', async () => {
    const w = await mountRail({ VITE_DISABLE_MARKETPLACE: '', VITE_DISABLE_REG_IMPORT: 'true' })
    const entries = await importEntries(w)

    expect(entries).toHaveLength(1)
    expect(entries[0]).toContain('Marketplace')
    w.unmount()
  })

  it('drops the Add from… submenu when both are disabled, keeping the rest of Options', async () => {
    // Options itself must survive: it is the only route to "New template".
    const w = await mountRail({ VITE_DISABLE_MARKETPLACE: 'true', VITE_DISABLE_REG_IMPORT: 'true' })
    await w.find('.om-trigger').trigger('click')

    expect(w.find('.om-trigger').exists()).toBe(true)
    expect(w.find('.om-sub-wrap').exists()).toBe(false)
    expect(w.findAll('.om-item').map(e => e.text()).some(t => t.includes('New template'))).toBe(true)
    w.unmount()
  })

  it('shows both entries by default', async () => {
    const w = await mountRail({ VITE_DISABLE_MARKETPLACE: '', VITE_DISABLE_REG_IMPORT: '' })
    expect(await importEntries(w)).toHaveLength(2)
    w.unmount()
  })
})

it('emits url and sameOrigin for a template, not just for snippets', async () => {
  // Regression: the template path once dropped these two arguments, so a third-party
  // template loaded with no trust prompt and no provenance recorded.
  const w = await mountWith([{ id: 't1', kind: 'template', name: 'T', url: 'a.xml' }])
  clickPrimary()
  await settle()

  const args = w.emitted('template')?.[0]
  expect(args).toBeTruthy()
  expect(args).toHaveLength(4)                             // xml, entry, url, sameOrigin
  expect(args![2]).toBe('https://cdn.example.com/catalog/a.xml')
  expect(args![3]).toBe(false)                             // off-origin: gate must fire
  w.unmount()
})

it('resolves an entry URL that climbs out of the catalog directory', async () => {
  // The bundled catalog points at ../Windows.xml, one level above itself.
  vi.resetModules()
  vi.stubEnv('VITE_MARKETPLACE_URL', '/marketplace/index.json')
  vi.stubEnv('VITE_MARKETPLACE_DISABLE_BUNDLED', '')
  const spy = vi.fn(async (url: string) =>
    url.endsWith('index.json')
      ? new Response(JSON.stringify({ schemaVersion: 1, entries: [
          { id: 'd', kind: 'template', name: 'Default Template', url: '../Windows.xml' }] }), { status: 200 })
      : new Response('<Items></Items>', { status: 200 }))
  vi.stubGlobal('fetch', spy)

  const MarketplaceDialog = (await import('../../src/components/MarketplaceDialog.vue')).default
  const w = mount(MarketplaceDialog, { props: { visible: true }, attachTo: document.body })
  await settle()
  clickPrimary()
  await settle()

  expect(spy.mock.calls.map(c => c[0])).toContain('/Windows.xml')
  expect(w.emitted('template')?.[0]?.[2]).toBe('/Windows.xml')
  w.unmount()
})

it('emits the same four arguments for a snippet', async () => {
  const w = await mountWith([{ id: 's1', kind: 'snippet', name: 'S', url: 'sub/b.xml' }])
  clickPrimary()
  await settle()

  const args = w.emitted('snippet')?.[0]
  expect(args).toHaveLength(4)
  expect(args![2]).toBe('https://cdn.example.com/catalog/sub/b.xml')
  expect(args![3]).toBe(false)
  w.unmount()
})

it('uses a fixed size so it does not resize as the catalog loads', async () => {
  const w = await mountWith([{ id: 't1', kind: 'template', name: 'T', url: 'a.xml' }])
  const style = (document.querySelector('.dialog') as HTMLElement).style

  expect(style.width).toBe('960px')
  expect(style.height).toBe('640px')   // 2:3 of the width
  w.unmount()
})

it('marks the source as external in the detail pane', async () => {
  const w = await mountWith([{ id: 't1', kind: 'template', name: 'T', url: 'a.xml' }])
  expect(document.body.textContent).toContain('External source')
  expect(document.body.textContent).toContain('cdn.example.com')
  w.unmount()
})

it('surfaces a CORS-flavoured message when the catalog cannot be reached', async () => {
  vi.resetModules()
  vi.stubEnv('VITE_MARKETPLACE_URL', INDEX)
  vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')))

  const MarketplaceDialog = (await import('../../src/components/MarketplaceDialog.vue')).default
  const w = mount(MarketplaceDialog, { props: { visible: true }, attachTo: document.body })
  await settle()

  expect(document.body.textContent).toContain('CORS')
  expect(document.querySelector('.mk-status--error')).not.toBeNull()
  w.unmount()
})

it('skips catalog entries that are missing required fields', async () => {
  const w = await mountWith([
    { id: 'ok', kind: 'snippet', name: 'Good', url: 'a.xml' },
    { id: 'bad', kind: 'snippet', name: 'No URL' },
    { kind: 'snippet', name: 'No id', url: 'c.xml' },
    { id: 'weird', kind: 'script', name: 'Unknown kind', url: 'd.xml' }
  ])
  expect(document.querySelectorAll('.mk-item')).toHaveLength(1)
  expect(document.body.textContent).toContain('Good')
  w.unmount()
})

/**
 * Authors write multi-line <Description> blocks (the bundled VisualEffects snippet puts
 * an "IMPORTANT:" caveat on its own line). HTML collapses newlines by default, which ran
 * the caveat into the prose. The detail pane opts into pre-line; the list row does not,
 * because it is clamped to 2 lines and a break there would spend one on a short sentence.
 */
it('keeps line breaks in the detail description, but not in the clamped list row', async () => {
  const w = await mountWith([{
    id: 'multi', kind: 'snippet', name: 'Multi', url: 'a.xml',
    description: 'First line.\nIMPORTANT: second line.'
  }])

  // The newline must reach the DOM: nothing along the way may collapse it.
  const detail = document.querySelector('.mk-detail-desc') as HTMLElement
  expect(detail).not.toBeNull()
  expect(detail.textContent).toContain('First line.\nIMPORTANT: second line.')
  w.unmount()

  // Whether it is *displayed* is down to white-space, and jsdom does not apply
  // <style scoped>, so getComputedStyle would report '' whatever the CSS said.
  // Assert on the stylesheet itself instead of testing jsdom.
  expect(dialogSource).toMatch(/\.mk-detail-desc\s*\{[^}]*white-space:\s*pre-line/)
  expect(dialogSource).not.toMatch(/\.mk-item-desc\s*\{[^}]*white-space:\s*pre-line/)
})
