import { describe, it, expect } from 'vitest'
import { serializeXml } from '../../src/core/serializer'
import { parseXml } from '../../src/core/parser'
import type { TemplateDocument } from '../../src/core/types'

const FULL_XML = `<?xml version="1.0" encoding="utf-8"?>
<Items>
  <SupportedOS>
    <OS>
      <Tag>Windows11</Tag>
      <Name>Windows 11</Name>
      <Abbreviation>W11</Abbreviation>
      <ServerOS>0</ServerOS>
      <Builds>
        <BuildStartsWith>21</BuildStartsWith>
      </Builds>
    </OS>
  </SupportedOS>
  <Item>
    <Name>B Item</Name>
    <Description>Second</Description>
    <Type>Service</Type>
    <Category>Test</Category>
    <Order>50</Order>
    <OS>
      <Windows11>
        <Execute>1</Execute>
        <Physical>1</Physical>
        <Virtual>0</Virtual>
      </Windows11>
    </OS>
    <Service>
      <Name>svc</Name>
      <Action>Disabled</Action>
    </Service>
  </Item>
  <Item>
    <Name>A Item</Name>
    <Description>First</Description>
    <Type>Service</Type>
    <Category>Test</Category>
    <Order>50</Order>
    <OS></OS>
    <Service>
      <Name>svcA</Name>
      <Action>Automatic</Action>
    </Service>
  </Item>
</Items>`

describe('serializeXml: XML declaration and structure', () => {
  it('starts with XML declaration', () => {
    const xml = serializeXml(parseXml(FULL_XML))
    expect(xml.startsWith('<?xml version="1.0" encoding="utf-8"?>')).toBe(true)
  })

  it('wraps in <Items>', () => {
    const xml = serializeXml(parseXml(FULL_XML))
    expect(xml).toContain('<Items>')
    expect(xml).toContain('</Items>')
  })
})

describe('serializeXml: SupportedOS', () => {
  it('writes Tag, Name, Abbreviation, ServerOS, BuildStartsWith', () => {
    const xml = serializeXml(parseXml(FULL_XML))
    expect(xml).toContain('<Tag>Windows11</Tag>')
    expect(xml).toContain('<Name>Windows 11</Name>')
    expect(xml).toContain('<Abbreviation>W11</Abbreviation>')
    expect(xml).toContain('<ServerOS>0</ServerOS>')
    expect(xml).toContain('<BuildStartsWith>21</BuildStartsWith>')
  })
})

describe('serializeXml: OS mapping', () => {
  it('always writes Execute, Physical, Virtual when OS is supported', () => {
    const xml = serializeXml(parseXml(FULL_XML))
    expect(xml).toContain('<Execute>1</Execute>')
    expect(xml).toContain('<Physical>1</Physical>')
    expect(xml).toContain('<Virtual>0</Virtual>')
  })

  it('omits OS tag entirely when not supported', () => {
    const xml = serializeXml(parseXml(FULL_XML))
    // "A Item" has no OS mappings, so Windows11 should not appear for it
    // Verify the structure contains exactly one Windows11 block
    const count = (xml.match(/<Windows11>/g) || []).length
    expect(count).toBe(1)
  })
})

describe('serializeXml: item sort order', () => {
  it('sorts by Order asc then Name A-Z', () => {
    const xml = serializeXml(parseXml(FULL_XML))
    const aIdx = xml.indexOf('<Name>A Item</Name>')
    const bIdx = xml.indexOf('<Name>B Item</Name>')
    expect(aIdx).toBeLessThan(bIdx)
  })
})

describe('serializeXml: PowerShell CDATA', () => {
  it('wraps script in CDATA', () => {
    const doc: TemplateDocument = {
      metadata: null,
      supportedOs: [],
      items: [{
        id: '1', name: 'PS', description: '', type: 'PowerShell', typeRaw: 'PowerShell',
        category: 'C', order: 100, os: {},
        payload: { type: 'PowerShell', engine: 'powershell', script: 'Write-Host "hi"' }
      }]
    }
    const xml = serializeXml(doc)
    expect(xml).toContain('<![CDATA[Write-Host "hi"]]>')
  })
})

describe('serializeXml: XML escaping', () => {
  it('escapes & < > in text values', () => {
    const doc: TemplateDocument = {
      metadata: null,
      supportedOs: [],
      items: [{
        id: '1', name: 'A & B', description: '', type: 'Service', typeRaw: 'Service',
        category: 'C', order: 100, os: {},
        payload: { type: 'Service', name: 'svc', action: 'Disabled' }
      }]
    }
    const xml = serializeXml(doc)
    expect(xml).toContain('<Name>A &amp; B</Name>')
  })
})

describe('serializeXml: round trip', () => {
  it('parse → serialize → parse produces equivalent document', () => {
    const original = parseXml(FULL_XML)
    const reparsed = parseXml(serializeXml(original))
    expect(reparsed.supportedOs[0].tag).toBe(original.supportedOs[0].tag)
    expect(reparsed.items.map(i => i.name).sort()).toEqual(original.items.map(i => i.name).sort())
    expect(reparsed.items.find(i => i.name === 'B Item')!.os['Windows11']).toEqual(
      original.items.find(i => i.name === 'B Item')!.os['Windows11']
    )
  })
})

describe('serializeXml: Metadata round-trip', () => {
  const WITH_META = `<?xml version="1.0" encoding="utf-8"?>
<Items>
  <Metadata>
    <Version>2026.429.2230</Version>
    <SchemaVersion>1</SchemaVersion>
  </Metadata>
  <SupportedOS></SupportedOS>
</Items>`

  it('preserves Metadata through parse -> serialize', () => {
    const out = serializeXml(parseXml(WITH_META))
    expect(out).toContain('<Version>2026.429.2230</Version>')
    expect(out).toContain('<SchemaVersion>1</SchemaVersion>')
    expect(parseXml(out).metadata).toMatchObject({ version: '2026.429.2230', schemaVersion: '1' })
  })

  it('round-trips the descriptive fields', () => {
    const xml = `<?xml version="1.0" encoding="utf-8"?>
<Items>
  <Metadata>
    <Version>2026.429.2230</Version>
    <SchemaVersion>1</SchemaVersion>
    <Id>abc-123</Id>
    <Name>My Snippet</Name>
    <Description>Does a thing.</Description>
    <Author>Someone</Author>
    <Category>Privacy</Category>
    <Tags><Tag>a</Tag><Tag>b</Tag></Tags>
  </Metadata>
  <SupportedOS></SupportedOS>
</Items>`
    const original = parseXml(xml)
    expect(parseXml(serializeXml(original)).metadata).toEqual(original.metadata)
  })

  it('omits descriptive fields that are empty, rather than writing blank elements', () => {
    const doc: TemplateDocument = {
      metadata: { version: '1', schemaVersion: '1', id: '', name: '', description: '', author: '', category: '', tags: [] },
      supportedOs: [], items: []
    }
    const out = serializeXml(doc)
    expect(out).toContain('<Version>1</Version>')
    for (const t of ['<Id>', '<Name>', '<Description>', '<Author>', '<Category>', '<Tags>']) {
      expect(out).not.toContain(t)
    }
  })

  it('emits Metadata before SupportedOS', () => {
    const out = serializeXml(parseXml(WITH_META))
    expect(out.indexOf('<Metadata>')).toBeLessThan(out.indexOf('<SupportedOS>'))
  })

  it('emits no Metadata block when the document has none', () => {
    const doc: TemplateDocument = { metadata: null, supportedOs: [], items: [] }
    expect(serializeXml(doc)).not.toContain('<Metadata>')
  })
})
