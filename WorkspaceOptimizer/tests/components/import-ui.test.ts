import { describe, it, expect, afterEach, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import MergeTable from '../../src/components/MergeTable.vue'
import MergePreviewDialog from '../../src/components/MergePreviewDialog.vue'
import WhatsNewDialog from '../../src/components/WhatsNewDialog.vue'
import OptionsMenu from '../../src/components/OptionsMenu.vue'
import { buildMergePlan } from '../../src/core/merge'
import type { TemplateItem, TemplateDocument } from '../../src/core/types'

/**
 * Focused checks on the import UI. These exist because the trust gate is a security
 * control: "Import is disabled until the user acknowledges external content" is a
 * claim worth asserting rather than eyeballing.
 *
 * Dialogs teleport to body, so assertions read from document.body and each test
 * unmounts to keep the DOM clean.
 */

function item(name: string, svc: string): TemplateItem {
  return {
    id: crypto.randomUUID(), name, description: '', type: 'Service', typeRaw: 'Service',
    category: 'C', order: 100, os: { Windows11: { execute: true, physical: true, virtual: true } },
    payload: { type: 'Service', name: svc, action: 'Disabled' }
  }
}

function doc(items: TemplateItem[] = []): TemplateDocument {
  return {
    metadata: null,
    supportedOs: [{ tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }],
    items
  }
}

const importButton = () => document.querySelectorAll('.mp-actions .dlg-btn')[1] as HTMLButtonElement

afterEach(() => { document.body.innerHTML = '' })

it('MergeTable shows a status per row and honours the quick-select chips', async () => {
  const plan = buildMergePlan(doc([item('Existing', 'dup')]), [item('A', 'a'), item('B', 'dup')])
  const w = mount(MergeTable, { props: { rows: plan.rows } })

  expect(w.findAll('tbody tr')).toHaveLength(2)
  expect(w.text()).toContain('new')
  expect(w.text()).toContain('duplicate')
  expect(w.text()).toContain('1 of 2 selected')   // only the new row starts selected

  const chips = w.findAll('.mt-chips button')
  await chips[1].trigger('click')                  // All
  expect(plan.rows.every(r => r.selected)).toBe(true)
  await chips[2].trigger('click')                  // None
  expect(plan.rows.some(r => r.selected)).toBe(false)
  await chips[0].trigger('click')                  // New only
  expect(plan.rows.filter(r => r.selected).map(r => r.status)).toEqual(['new'])
})

describe('MergeTable order editing', () => {
  const rows = () => buildMergePlan(doc(), [item('A', 'a'), item('B', 'b'), item('C', 'c')]).rows

  it('hides the order column and bulk bar unless asked for', () => {
    const w = mount(MergeTable, { props: { rows: rows() } })
    expect(w.find('.c-order').exists()).toBe(false)
    expect(w.find('.mt-bulk').exists()).toBe(false)
  })

  it('edits one row without touching the others', async () => {
    const r = rows()
    const w = mount(MergeTable, { props: { rows: r, showOrder: true } })

    const input = w.findAll('.c-order input')[1]
    await input.setValue('75')
    expect(r[1].item.order).toBe(75)
    expect(r[0].item.order).toBe(100)   // untouched
  })

  it('clamps an edited order to the range the validator accepts', async () => {
    const r = rows()
    const w = mount(MergeTable, { props: { rows: r, showOrder: true } })
    const input = w.findAll('.c-order input')[0]

    await input.setValue('999999')
    expect(r[0].item.order).toBe(99999)
    await input.setValue('abc')
    expect(r[0].item.order).toBe(0)
  })

  it('applies a bulk order to the selected rows only', async () => {
    const r = rows()
    r[2].selected = false
    const w = mount(MergeTable, { props: { rows: r, showOrder: true } })

    await w.find('.mt-bulk-inp').setValue('60')
    await w.find('.mt-bulk button').trigger('click')

    expect(r.map(x => x.item.order)).toEqual([60, 60, 100])   // the deselected row keeps its own
  })

  it('refuses a bulk order outside 0-99999', async () => {
    const r = rows()
    const w = mount(MergeTable, { props: { rows: r, showOrder: true } })
    const btn = w.find('.mt-bulk button')

    await w.find('.mt-bulk-inp').setValue('100000')
    expect(btn.attributes('disabled')).toBeDefined()

    await w.find('.mt-bulk-inp').setValue('50')
    expect(btn.attributes('disabled')).toBeUndefined()
  })

  it('disables the bulk button when nothing is selected', async () => {
    const r = rows()
    for (const x of r) x.selected = false
    const w = mount(MergeTable, { props: { rows: r, showOrder: true } })

    await w.find('.mt-bulk-inp').setValue('50')
    expect(w.find('.mt-bulk button').attributes('disabled')).toBeDefined()
  })

  it('keeps a snippet\'s names read-only while allowing order edits', () => {
    const w = mount(MergeTable, { props: { rows: rows(), showOrder: true } })
    expect(w.find('.c-name input').exists()).toBe(false)   // author's naming preserved
    expect(w.find('.c-order input').exists()).toBe(true)
  })
})

describe('MergeTable category editing', () => {
  const rows = () => buildMergePlan(doc(), [item('A', 'a'), item('B', 'b'), item('C', 'c')]).rows

  it('hides the category column and bulk field unless asked for', () => {
    const w = mount(MergeTable, { props: { rows: rows() } })
    expect(w.find('.c-cat').exists()).toBe(false)
    expect(w.find('.mt-bulk-cat').exists()).toBe(false)
  })

  it('edits one row without touching the others', async () => {
    const r = rows()
    const w = mount(MergeTable, { props: { rows: r, showCategory: true } })

    await w.findAll('.c-cat input')[1].setValue('Privacy')
    expect(r[1].item.category).toBe('Privacy')
    expect(r[0].item.category).toBe('C')
  })

  it('applies a bulk category to the selected rows only', async () => {
    const r = rows()
    r[2].selected = false
    const w = mount(MergeTable, { props: { rows: r, showCategory: true } })

    await w.find('.mt-bulk-cat').setValue('  Visual Effects  ')
    await w.find('.mt-bulk .dlg-btn').trigger('click')

    // Trimmed, and the deselected row keeps its own value.
    expect(r.map(x => x.item.category)).toEqual(['Visual Effects', 'Visual Effects', 'C'])
  })

  it('refuses a blank bulk category', async () => {
    const r = rows()
    const w = mount(MergeTable, { props: { rows: r, showCategory: true } })
    const btn = w.find('.mt-bulk .dlg-btn')

    await w.find('.mt-bulk-cat').setValue('   ')
    expect(btn.attributes('disabled')).toBeDefined()

    await w.find('.mt-bulk-cat').setValue('Privacy')
    expect(btn.attributes('disabled')).toBeUndefined()
  })

  it('hints the incoming category when every row shares one', () => {
    const w = mount(MergeTable, { props: { rows: rows(), showCategory: true } })
    expect(w.find('.mt-bulk-cat').attributes('placeholder')).toBe('C')
  })

  it('shows both bulk setters when category and order are editable', () => {
    const w = mount(MergeTable, { props: { rows: rows(), showCategory: true, showOrder: true } })
    expect(w.findAll('.mt-bulk .dlg-btn')).toHaveLength(2)
    expect(w.find('.mt-bulk-cat').exists()).toBe(true)
    expect(w.find('.mt-bulk-inp').exists()).toBe(true)
  })
})

it('blocks import of cross-origin content until it is acknowledged', async () => {
  const plan = buildMergePlan(doc(), [item('A', 'a')])
  const w = mount(MergePreviewDialog, {
    props: {
      visible: true, plan,
      source: { id: 'mp:x', kind: 'marketplace', label: 'X', origin: 'evil.example.com', sameOrigin: false, originLabel: 'evil.example.com' }
    },
    attachTo: document.body
  })

  expect(document.body.textContent).toContain('not part of this site')
  expect(importButton().disabled).toBe(true)

  ;(document.querySelector('.trust-ack input') as HTMLInputElement).click()
  await w.vm.$nextTick()
  expect(importButton().disabled).toBe(false)

  w.unmount()
})

it('needs no acknowledgement for same-origin content', () => {
  const plan = buildMergePlan(doc(), [item('A', 'a')])
  const w = mount(MergePreviewDialog, {
    props: {
      visible: true, plan,
      source: { id: 'mp:x', kind: 'marketplace', label: 'X', origin: '', sameOrigin: true, originLabel: 'localhost' }
    },
    attachTo: document.body
  })

  expect(document.body.textContent).not.toContain('not part of this site')
  expect(importButton().disabled).toBe(false)
  w.unmount()
})

it('offers to add an OS definition the snippet carries', () => {
  const incoming = item('Server tweak', 'svc')
  incoming.os = { Server2019: { execute: true, physical: true, virtual: true } }
  const plan = buildMergePlan(doc(), [incoming], [
    { tag: 'Server2019', name: 'Windows Server 2019', abbreviation: 'WS2019', isServerOs: true, buildStartsWith: ['17'] }
  ])
  const w = mount(MergePreviewDialog, {
    props: { visible: true, plan, source: { id: 'mp:x', kind: 'marketplace', label: 'X', origin: '', sameOrigin: true, originLabel: '' } },
    attachTo: document.body
  })

  expect(document.body.textContent).toContain('Add')
  expect(document.body.textContent).toContain('Windows Server 2019')
  w.unmount()
})

it('still offers to add an OS the snippet did not define, flagged as incomplete', async () => {
  const incoming = item('Orphan', 'svc')
  incoming.os = { Server2012: { execute: true, physical: true, virtual: true } }
  const plan = buildMergePlan(doc(), [incoming])
  const w = mount(MergePreviewDialog, {
    props: { visible: true, plan, source: { id: 'mp:x', kind: 'marketplace', label: 'X', origin: '', sameOrigin: true, originLabel: '' } },
    attachTo: document.body
  })

  // The checkbox exists, and the note explains why it arrives disabled.
  expect(document.querySelector('.mp-os-add')).not.toBeNull()
  expect(document.querySelector('.mp-os-note')?.textContent).toContain('no build numbers')
  expect(document.querySelector('.mp-os-warn')?.textContent).toContain('is removed from imported items')

  // Ticking it drops the "will be removed" warning.
  ;(document.querySelector('.mp-os-add input') as HTMLInputElement).click()
  await w.vm.$nextTick()
  expect(document.querySelector('.mp-os-warn')).toBeNull()

  w.unmount()
})

it('renders the changelog with tagged entries', () => {
  const w = mount(WhatsNewDialog, { props: { visible: true }, attachTo: document.body })
  expect(document.body.textContent).toContain('Unreleased')
  expect(document.querySelectorAll('.wn-tag--new').length).toBeGreaterThan(0)
  expect(document.querySelectorAll('.wn-tag--fix').length).toBeGreaterThan(0)
  w.unmount()
})

it('styles changelog section headings instead of dropping them into body text', () => {
  // '### Marketplace' also starts with '## ', so the version branch would swallow it.
  const w = mount(WhatsNewDialog, { props: { visible: true }, attachTo: document.body })

  const sections = [...document.querySelectorAll('.wn-section')].map(e => e.textContent)
  expect(sections.length).toBeGreaterThan(0)
  expect(sections).toContain('Marketplace')

  const versions = [...document.querySelectorAll('.wn-version')].map(e => e.textContent)
  expect(versions).toContain('Unreleased')
  expect(versions).not.toContain('Marketplace')   // not mistaken for a version heading
  w.unmount()
})

describe('Properties toolbar button', () => {
  const W11 = { tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }

  async function railWith(metadata: TemplateDocument['metadata']) {
    vi.stubGlobal('matchMedia', () => ({ matches: false, addEventListener() {}, removeEventListener() {} }))
    const { documentStore } = await import('../../src/store/document')
    documentStore.load({ metadata, supportedOs: [W11], items: [] }, 't.xml')
    const IconRail = (await import('../../src/components/IconRail.vue')).default
    return mount(IconRail)
  }

  const btn = (w: ReturnType<typeof mount>) => w.findAll('.tb-btn').find(b => b.text() === 'Properties')!

  it('turns red and bold only while a required field is missing', async () => {
    const w = await railWith(null)
    expect(btn(w).classes()).toContain('tb-btn--alert')
    expect(btn(w).attributes('data-tooltip')).toContain('required before download')
    w.unmount()
  })

  it('looks like any other button once the fields are filled', async () => {
    const w = await railWith({ version: '1', schemaVersion: '1', id: 'x', name: 'N', description: 'D', author: 'A', category: '', tags: [] })
    expect(btn(w).classes()).not.toContain('tb-btn--alert')
    w.unmount()
  })

  it('stays neutral when no document is open', async () => {
    vi.stubGlobal('matchMedia', () => ({ matches: false, addEventListener() {}, removeEventListener() {} }))
    const { documentStore } = await import('../../src/store/document')
    documentStore.document = null
    const IconRail = (await import('../../src/components/IconRail.vue')).default
    const w = mount(IconRail)
    expect(btn(w).classes()).not.toContain('tb-btn--alert')
    w.unmount()
  })
})

it('the toolbar exposes both import routes through one Add from… menu', async () => {
  // Regression: there must be no standalone Marketplace button, both routes live
  // behind the single menu, positioned between Open Template and Download XML.
  // jsdom has no matchMedia, which IconRail uses for the theme toggle.
  vi.stubGlobal('matchMedia', () => ({
    matches: false, addEventListener() {}, removeEventListener() {}
  }))

  const IconRail = (await import('../../src/components/IconRail.vue')).default
  const w = mount(IconRail)

  const labels = w.findAll('.tb-btn').map(b => b.text())
  expect(labels).toContain('Open Template')
  expect(labels).not.toContain('Marketplace')
  expect(labels).not.toContain('Import .reg file')
  expect(w.findAll('.om-trigger')).toHaveLength(1)

  // Occasional actions live in Options only, so the toolbar stays short.
  expect(labels).not.toContain('Manage OS')
  expect(labels).not.toContain('PDF Report')

  // Options leads, so the first thing a new user sees offers a way to start.
  const order = [...w.element.querySelectorAll('.tb-btn, .om-trigger')].map(e => e.textContent?.trim())
  expect(order.findIndex(t => t?.startsWith('Options')))
    .toBeLessThan(order.findIndex(t => t === 'Open Template'))

  // Both import routes are reachable through the submenu.
  await w.find('.om-trigger').trigger('click')
  await w.find('.om-sub-wrap').trigger('mouseenter')
  const entries = w.findAll('.om-submenu .om-item').map(e => e.text())
  expect(entries[0]).toContain('Marketplace')
  expect(entries[1]).toContain('Import .reg file')

  w.unmount()
  vi.unstubAllGlobals()
})

describe('PropertiesDialog', () => {
  const W11 = { tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }

  async function open(metadata: TemplateDocument['metadata']) {
    const { documentStore } = await import('../../src/store/document')
    documentStore.load({ metadata, supportedOs: [W11], items: [] }, 't.xml')
    const PropertiesDialog = (await import('../../src/components/PropertiesDialog.vue')).default
    const w = mount(PropertiesDialog, { props: { visible: true }, attachTo: document.body })
    await w.vm.$nextTick()
    return { w, documentStore }
  }

  it('generates an Id when the document has none', async () => {
    const { w } = await open(null)
    const id = (document.querySelectorAll('.pr-field input')[0] as HTMLInputElement).value
    expect(id).toMatch(/^[0-9a-f-]{36}$/)
    w.unmount()
  })

  it('keeps an existing Id rather than replacing it', async () => {
    const { w } = await open({ version: '1', schemaVersion: '1', id: 'keep-me', name: 'N', description: 'D', author: 'A', category: '', tags: [] })
    expect((document.querySelectorAll('.pr-field input')[0] as HTMLInputElement).value).toBe('keep-me')
    w.unmount()
  })

  it('names the fields still missing', async () => {
    const { w } = await open(null)
    expect(document.querySelector('.pr-warn')?.textContent).toContain('Name, Description, Author')
    expect(document.querySelectorAll('.pr-missing')).toHaveLength(3)
    w.unmount()
  })

  it('saves trimmed values and splits tags on commas', async () => {
    const { w, documentStore } = await open(null)
    const inputs = [...document.querySelectorAll('.pr-body input, .pr-body textarea')] as HTMLInputElement[]
    const set = (el: HTMLInputElement, v: string) => { el.value = v; el.dispatchEvent(new Event('input')) }

    set(inputs[1], '  My Template  ')          // Name
    set(inputs[2], ' Does a thing. ')          // Description (textarea)
    set(inputs[3], ' Someone ')                // Author
    set(inputs[4], ' Baseline ')               // Category
    set(inputs[5], ' a , b ,, c ')             // Tags
    await w.vm.$nextTick()

    ;(document.querySelectorAll('.dlg-footer .dlg-btn')[1] as HTMLButtonElement).click()
    await w.vm.$nextTick()

    expect(documentStore.document!.metadata).toMatchObject({
      name: 'My Template', description: 'Does a thing.', author: 'Someone',
      category: 'Baseline', tags: ['a', 'b', 'c']
    })
    expect(documentStore.dirty).toBe(true)
    w.unmount()
  })

  it('discards on Cancel', async () => {
    const { w, documentStore } = await open(null)
    const name = document.querySelectorAll('.pr-body input')[1] as HTMLInputElement
    name.value = 'Typed'; name.dispatchEvent(new Event('input'))
    await w.vm.$nextTick()

    ;(document.querySelectorAll('.dlg-footer .dlg-btn')[0] as HTMLButtonElement).click()
    await w.vm.$nextTick()

    expect(documentStore.document!.metadata).toBeNull()   // nothing committed
    w.unmount()
  })
})

it('OSDialog closes on Escape and discards, like Cancel', async () => {
  // It had no Escape handler before the BaseDialog migration.
  const OSDialog = (await import('../../src/components/OSDialog.vue')).default
  const w = mount(OSDialog, { props: { visible: true }, attachTo: document.body })

  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
  await w.vm.$nextTick()

  expect(w.emitted('update:visible')).toEqual([[false]])
  expect(w.emitted('saved')).toBeFalsy()      // discarded, not saved
  w.unmount()
})

it('PdfDialog closes on Escape without generating', async () => {
  const PdfDialog = (await import('../../src/components/PdfDialog.vue')).default
  const w = mount(PdfDialog, { props: { visible: true }, attachTo: document.body })

  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
  await w.vm.$nextTick()

  expect(w.emitted('update:visible')).toEqual([[false]])
  w.unmount()
})

it('AboutDialog leaves Escape to the nested What\'s New dialog', async () => {
  const AboutDialog = (await import('../../src/components/AboutDialog.vue')).default
  const w = mount(AboutDialog, { props: { visible: true }, attachTo: document.body })

  // Open What's New from within About.
  ;(document.querySelector('.about-whatsnew') as HTMLButtonElement).click()
  await w.vm.$nextTick()
  expect(document.body.textContent).toContain('Unreleased')

  // Escape must close only the inner dialog, leaving About open.
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
  await w.vm.$nextTick()
  expect(w.emitted('update:visible')).toBeFalsy()
  expect(document.body.textContent).not.toContain('Unreleased')

  // A second Escape, now that only About is open, closes it.
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
  await w.vm.$nextTick()
  expect(w.emitted('update:visible')).toEqual([[false]])

  w.unmount()
})

describe('OptionsMenu', () => {
  it('drops its tooltip while open, so it cannot cover the first entry', async () => {
    const w = mount(OptionsMenu)
    const trigger = w.find('.om-trigger')
    expect(trigger.attributes('data-tooltip')).toBeDefined()

    await trigger.trigger('click')
    expect(trigger.attributes('data-tooltip')).toBeUndefined()

    await trigger.trigger('click')
    expect(trigger.attributes('data-tooltip')).toBeDefined()
  })

  it('offers the template actions a new user needs first', async () => {
    const w = mount(OptionsMenu)
    await w.find('.om-trigger').trigger('click')

    const labels = w.findAll('.om-item').map(b => b.text())
    expect(labels[0]).toContain('New template')      // the empty-start route
    expect(labels[1]).toContain('New from default')
    expect(labels[2]).toContain('Open template')
  })

  it('emits and closes when an action is chosen', async () => {
    const w = mount(OptionsMenu)
    await w.find('.om-trigger').trigger('click')
    await w.findAll('.om-item')[0].trigger('click')

    expect(w.emitted('new')).toBeTruthy()
    expect(w.find('.om-menu').exists()).toBe(false)
  })

  it('opens the Add from… submenu on hover', async () => {
    const w = mount(OptionsMenu)
    await w.find('.om-trigger').trigger('click')
    expect(w.find('.om-submenu').exists()).toBe(false)

    await w.find('.om-sub-wrap').trigger('mouseenter')
    expect(w.find('.om-submenu').exists()).toBe(true)
    expect(w.find('.om-submenu').text()).toContain('Marketplace')
    expect(w.find('.om-submenu').text()).toContain('Import .reg file')
  })

  it('emits from the submenu and closes the whole menu', async () => {
    const w = mount(OptionsMenu)
    await w.find('.om-trigger').trigger('click')
    await w.find('.om-sub-wrap').trigger('mouseenter')
    await w.findAll('.om-submenu .om-item')[1].trigger('click')   // Import .reg file

    expect(w.emitted('regfile')).toBeTruthy()
    expect(w.find('.om-menu').exists()).toBe(false)
  })

  it('disables the actions that need an open document', async () => {
    const { documentStore } = await import('../../src/store/document')
    documentStore.document = null

    const w = mount(OptionsMenu)
    await w.find('.om-trigger').trigger('click')
    const byText = (t: string) => w.findAll('.om-item').find(b => b.text().includes(t))!

    expect(byText('Manage OS').attributes('disabled')).toBeDefined()
    expect(byText('PDF report').attributes('disabled')).toBeDefined()
    // Starting a template must always be reachable, that was the original bug.
    expect(byText('New template').attributes('disabled')).toBeUndefined()

    await byText('Manage OS').trigger('click')
    expect(w.emitted('manageos')).toBeFalsy()
  })

  it('enables them once a document with items is open', async () => {
    const { documentStore } = await import('../../src/store/document')
    documentStore.load({
      metadata: null,
      supportedOs: [{ tag: 'Windows11', name: 'W11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }],
      items: [item('A', 'a')]
    }, 't.xml')

    const w = mount(OptionsMenu)
    await w.find('.om-trigger').trigger('click')
    const byText = (t: string) => w.findAll('.om-item').find(b => b.text().includes(t))!

    expect(byText('Manage OS').attributes('disabled')).toBeUndefined()
    expect(byText('PDF report').attributes('disabled')).toBeUndefined()
  })
})

