import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import OSMappingTable from '../../src/components/OSMappingTable.vue'
import { documentStore } from '../../src/store/document'
import type { TemplateItem } from '../../src/core/types'

/**
 * Issue #4: ticking Execute before Physical or Virtual was silently discarded, and the
 * box still rendered as checked because its bound value never changed. The loss only
 * surfaced after navigating away and back.
 */

function item(): TemplateItem {
  return {
    id: 'i1', name: 'Test1', description: 'Test1', type: 'Service', typeRaw: 'Service',
    category: 'General', order: 100, os: {},
    payload: { type: 'Service', name: 'wuauserv', action: 'Disabled' }
  }
}

function mountTable() {
  return mount(OSMappingTable, { props: { item: documentStore.document!.items[0] } })
}

/** [supported, execute, physical, virtual] for the single OS row. */
function boxes(wrapper: ReturnType<typeof mountTable>) {
  return wrapper.findAll('.os-row')[0].findAll('input[type="checkbox"]')
}

function stored() {
  return documentStore.document!.items[0].os['WindowsServer2025']
}

beforeEach(() => {
  documentStore.load({
    metadata: null,
    supportedOs: [{ tag: 'WindowsServer2025', name: 'Windows Server 2025', abbreviation: 'WS2025', isServerOs: true, buildStartsWith: ['26'] }],
    items: [item()]
  }, 'test.xml')
})

describe('OSMappingTable execute checkbox', () => {

  it('disables Execute while Physical and Virtual are both unchecked', async () => {
    const wrapper = mountTable()
    const [supported, execute] = boxes(wrapper)

    await supported.setValue(true)

    expect((execute.element as HTMLInputElement).disabled).toBe(true)
    expect(stored()).toEqual({ execute: false, physical: false, virtual: false })
  })

  it('enables Execute once Physical is ticked, and the tick persists', async () => {
    const wrapper = mountTable()
    const [supported, execute, physical] = boxes(wrapper)

    await supported.setValue(true)
    await physical.setValue(true)
    expect((execute.element as HTMLInputElement).disabled).toBe(false)

    await execute.setValue(true)
    expect(stored()).toEqual({ execute: true, physical: true, virtual: false })
  })

  it('enables Execute on Virtual alone', async () => {
    const wrapper = mountTable()
    const [supported, execute, , virtual] = boxes(wrapper)

    await supported.setValue(true)
    await virtual.setValue(true)
    await execute.setValue(true)

    expect(stored()).toEqual({ execute: true, physical: false, virtual: true })
  })

  it('clears Execute when the last of Physical and Virtual is unticked', async () => {
    const wrapper = mountTable()
    const [supported, execute, physical] = boxes(wrapper)

    await supported.setValue(true)
    await physical.setValue(true)
    await execute.setValue(true)
    await physical.setValue(false)

    expect(stored().execute).toBe(false)
  })

  it('never renders Execute checked while the stored value is false', async () => {
    const wrapper = mountTable()
    const [supported, execute, physical] = boxes(wrapper)

    await supported.setValue(true)
    await physical.setValue(true)
    await execute.setValue(true)
    await physical.setValue(false)

    expect((execute.element as HTMLInputElement).checked).toBe(stored().execute)
  })

  it('drops the whole mapping when the OS is unticked', async () => {
    const wrapper = mountTable()
    const [supported, , physical] = boxes(wrapper)

    await supported.setValue(true)
    await physical.setValue(true)
    await supported.setValue(false)

    expect(stored()).toBeUndefined()
  })
})
