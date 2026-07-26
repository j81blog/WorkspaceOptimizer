import { it, expect, afterEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'

/**
 * Lives in its own file because it mocks the build-time `CHANGELOG.md?raw` import,
 * which needs vi.resetModules(). Doing that inside import-ui.test.ts handed the tests
 * after it a second copy of documentStore, so the isolation is deliberate. Same
 * reasoning as marketplace-dialog.test.ts.
 *
 * The changelog only grows: every release pushes the newest one further down, so
 * without collapsing, a user opening What's New eventually lands mid-history. The real
 * file has a single release today, hence the three-release stub.
 */

const CHANGELOG = [
  '# Changelog', '',
  '## 26.07.2026', '', '### Interface', '', 'NEW: Newest thing', 'FIX: Newest fix', '',
  '## 15.05.2026', '', '### Interface', '', 'NEW: Older thing', '',
  '## 02.03.2026', '', '### Interface', '', 'NEW: Oldest thing',
].join('\n')

async function mountDialog() {
  vi.resetModules()
  vi.doMock('../../../CHANGELOG.md?raw', () => ({ default: CHANGELOG }))
  const Dialog = (await import('../../src/components/WhatsNewDialog.vue')).default
  return mount(Dialog, { props: { visible: true }, attachTo: document.body })
}

const names = () => [...document.querySelectorAll('.wn-vname')].map(e => e.textContent!.trim())
const expanded = () =>
  [...document.querySelectorAll('.wn-version')].map(e => e.getAttribute('aria-expanded'))
const bodyText = () => document.body.textContent!

afterEach(() => {
  document.body.innerHTML = ''
  vi.doUnmock('../../../CHANGELOG.md?raw')
  vi.resetModules()
})

it('expands only the newest release and collapses the rest', async () => {
  const w = await mountDialog()

  expect(names()).toEqual(['26.07.2026', '15.05.2026', '02.03.2026'])
  expect(expanded()).toEqual(['true', 'false', 'false'])

  // Only the newest release's entries reach the DOM.
  expect(bodyText()).toContain('Newest thing')
  expect(bodyText()).not.toContain('Older thing')
  expect(bodyText()).not.toContain('Oldest thing')

  w.unmount()
})

it('counts the changes in every release, collapsed or not', async () => {
  const w = await mountDialog()
  const counts = [...document.querySelectorAll('.wn-count')].map(e => e.textContent!.trim())
  expect(counts).toEqual(['2 changes', '1 change', '1 change'])
  w.unmount()
})

it('expands an older release without collapsing the newest', async () => {
  const w = await mountDialog()

  await (document.querySelectorAll('.wn-version')[1] as HTMLButtonElement).click()
  await w.vm.$nextTick()

  expect(expanded()).toEqual(['true', 'true', 'false'])
  expect(bodyText()).toContain('Older thing')
  expect(bodyText()).toContain('Newest thing')
  expect(bodyText()).not.toContain('Oldest thing')

  w.unmount()
})

it('collapses the newest release when its heading is clicked', async () => {
  const w = await mountDialog()

  await (document.querySelectorAll('.wn-version')[0] as HTMLButtonElement).click()
  await w.vm.$nextTick()

  expect(expanded()).toEqual(['false', 'false', 'false'])
  expect(bodyText()).not.toContain('Newest thing')
  // The headings themselves stay, so the release is still reachable.
  expect(names()).toEqual(['26.07.2026', '15.05.2026', '02.03.2026'])

  w.unmount()
})
