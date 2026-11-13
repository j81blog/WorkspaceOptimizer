import { describe, it, expect } from 'vitest'
import { parseXml, findDroppedContent } from '../../src/core/parser'
import { serializeXml } from '../../src/core/serializer'
import { validate } from '../../src/core/validator'
import { parseReg } from '../../src/core/regParser'
import type { TemplateDocument, TemplateItem, ItemPayload } from '../../src/core/types'

const META = `<Metadata><Version>1</Version><SchemaVersion>1</SchemaVersion><Id>x</Id><Name>N</Name><Description>D</Description><Author>A</Author></Metadata>`
const OS = `<SupportedOS><OS><Tag>Windows11</Tag><Name>Windows 11</Name><Abbreviation>W11</Abbreviation><ServerOS>0</ServerOS><Builds><BuildStartsWith>22</BuildStartsWith></Builds></OS></SupportedOS>`

function file(items: string, extra = ''): string {
  return `<?xml version="1.0" encoding="utf-8"?><Items>${META}${OS}${items}${extra}</Items>`
}

function doc(payload: ItemPayload, over: Partial<TemplateItem> = {}): TemplateDocument {
  const item: TemplateItem = {
    id: 'i1', name: 'Item', description: '', type: payload.type, typeRaw: payload.type,
    category: 'General', order: 100, os: {}, payload, ...over
  }
  return {
    metadata: { version: '1', schemaVersion: '1', id: 'x', name: 'N', description: 'D', author: 'A', category: '', tags: [] },
    supportedOs: [{ tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }],
    items: [item]
  }
}

const reg = (over: Record<string, unknown> = {}): ItemPayload => ({
  type: 'Registry', hive: 'HKLM', path: 'SW\\T', name: 'v', action: 'SetValue', value: '1', registryType: 'DWord', ...over
} as ItemPayload)

const codes = (d: TemplateDocument) => validate(d).errors.map(e => e.code)

describe('#6 unknown item types', () => {
  const bogus = `<Item><Name>B</Name><Description></Description><Type>Bogus</Type><Category>C</Category><Order>1</Order><OS></OS><Bogus><Thing a="1">x &amp; y</Thing></Bogus></Item>`

  it('keeps the payload through parse, serialize, parse', () => {
    const first = parseXml(file(bogus))
    expect(first.items[0].payload).toMatchObject({ type: 'Unknown' })
    const second = parseXml(serializeXml(first))
    const p = second.items[0].payload
    expect(p.type === 'Unknown' && p.rawXml).toContain('<Thing a="1">x &amp; y</Thing>')
    expect(second.items[0].typeRaw).toBe('Bogus')
  })

  it('does not list an unknown item payload as dropped', () => {
    expect(findDroppedContent(file(bogus))).toEqual([])
  })
})

describe('dropped content detection', () => {
  const item = (inner: string) => `<Item><Name>I</Name><Type>Service</Type><Category>C</Category><Order>1</Order><OS></OS>${inner}</Item>`
  const svc = '<Service><Name>s</Name><Action>Disabled</Action></Service>'

  it('is empty for a clean file', () => {
    expect(findDroppedContent(file(item(svc)))).toEqual([])
  })
  it('reports comments', () => {
    expect(findDroppedContent(file(item(svc), '<!-- hi -->'))[0]).toMatch(/1 XML comment/)
  })
  it('reports unknown elements under Item, Metadata, OS and SupportedOS', () => {
    const xml = `<Items><Metadata><Name>N</Name><Mystery/></Metadata><SupportedOS><OS><Tag>W</Tag><Extra/></OS><Odd/></SupportedOS>${item(svc + '<Notes>x</Notes>')}</Items>`
    const out = findDroppedContent(xml).join('|')
    expect(out).toContain('<Mystery>')
    expect(out).toContain('<Extra>')
    expect(out).toContain('<Odd>')
    expect(out).toContain('<Notes> in item "I"')
  })
  it('reports unknown children of a per-item OS mapping', () => {
    const xml = `<Items><SupportedOS/><Item><Name>I</Name><Type>Service</Type><OS><Windows11><Execute>1</Execute><Wat>1</Wat></Windows11></OS>${svc}</Item></Items>`
    expect(findDroppedContent(xml).join('|')).toContain('<Wat>')
  })
})

describe('#17 OS tag must be an XML name', () => {
  it.each(['Win 11', '11', 'a<b', ''])('rejects %j', tag => {
    const d = doc(reg())
    d.supportedOs[0].tag = tag
    expect(codes(d)).toContain(tag === '' ? 'OS_TAG_REQUIRED' : 'OS_TAG_INVALID')
  })
  it('accepts Windows11, Server_2022 and Win-11.x', () => {
    for (const tag of ['Windows11', 'Server_2022', 'Win-11.x']) {
      const d = doc(reg())
      d.supportedOs[0].tag = tag
      expect(codes(d)).not.toContain('OS_TAG_INVALID')
    }
  })
})

describe('#18 default registry value', () => {
  it('allows an empty Name for SetValue and DeleteValue', () => {
    expect(codes(doc(reg({ name: '', registryType: 'String', value: 'x' })))).toEqual([])
    expect(codes(doc(reg({ name: '', action: 'DeleteValue' })))).toEqual([])
  })
  it('allows an empty Binary value', () => {
    expect(codes(doc(reg({ registryType: 'Binary', value: '' })))).toEqual([])
  })
  it('imports @=- and @="x" and an empty hex value', () => {
    const r = parseReg(`Windows Registry Editor Version 5.00\n[HKEY_LOCAL_MACHINE\\SOFTWARE\\T]\n@="x"\n@=-\n"a"=hex:\n`)
    expect(r.entries.map(e => e.name)).toEqual(['', '', 'a'])
  })
})

describe('#19 comment ending in a backslash', () => {
  it('does not swallow the next line', () => {
    const r = parseReg(`Windows Registry Editor Version 5.00\n[HKEY_LOCAL_MACHINE\\SOFTWARE\\T]\n; path is C:\\dir\\\n"a"=dword:00000001\n`)
    expect(r.entries.map(e => e.name)).toEqual(['a'])
  })
  it('still joins real continuations', () => {
    const r = parseReg(`Windows Registry Editor Version 5.00\n[HKEY_LOCAL_MACHINE\\SOFTWARE\\T]\n"a"=hex:01,\\\n  02\n`)
    expect(r.entries[0].value).toBe('01,02')
  })
})

describe('#20 validator gaps', () => {
  it('validates the hive', () => {
    expect(codes(doc(reg({ hive: 'HKCR' })))).toContain('ENUM_INVALID')
    for (const hive of ['HKLM', 'HKCU', 'HKU', 'HKU\\DefaultUser']) expect(codes(doc(reg({ hive })))).toEqual([])
  })
  it('range checks DWord', () => {
    expect(codes(doc(reg({ value: '4294967295' })))).toEqual([])
    expect(codes(doc(reg({ value: '0xFFFFFFFF' })))).toEqual([])
    expect(codes(doc(reg({ value: '4294967296' })))).toContain('FIELD_RANGE')
    expect(codes(doc(reg({ value: '0x100000000' })))).toContain('FIELD_RANGE')
  })
  it('range checks Qword with full precision', () => {
    expect(codes(doc(reg({ registryType: 'Qword', value: '18446744073709551615' })))).toEqual([])
    expect(codes(doc(reg({ registryType: 'Qword', value: '18446744073709551616' })))).toContain('FIELD_RANGE')
    expect(codes(doc(reg({ registryType: 'Qword', value: '0x10000000000000000' })))).toContain('FIELD_RANGE')
  })
  it('validates the PowerShell engine and treats whitespace as empty', () => {
    const ps = (engine: string, script: string): ItemPayload => ({ type: 'PowerShell', engine, script })
    expect(codes(doc(ps('pwsh', 'x')))).toEqual([])
    expect(codes(doc(ps('PowerShell', 'x')))).toEqual([])
    expect(codes(doc(ps('python', 'x')))).toContain('ENUM_INVALID')
    expect(codes(doc(ps('pwsh', '  \n\t ')))).toContain('FIELD_REQUIRED')
  })
})

describe('#21 characters invalid in XML', () => {
  it('flags control characters and names the item and field', () => {
    const d = doc({ type: 'PowerShell', engine: 'pwsh', script: 'a\u0001b' })
    const issue = validate(d).errors.find(e => e.code === 'XML_INVALID_CHAR')
    expect(issue?.message).toContain('Item "Item"')
    expect(issue?.message).toContain('script')
    expect(issue?.message).toContain('U+0001')
  })
  it('allows tab, LF and CR', () => {
    expect(codes(doc({ type: 'PowerShell', engine: 'pwsh', script: 'a\tb\r\nc' }))).toEqual([])
  })
  it('flags item names', () => {
    expect(codes(doc(reg(), { name: 'bad\u0000name' }))).toContain('XML_INVALID_CHAR')
  })
  it('round-trips a script containing ]]>', () => {
    const script = 'if ($a[$b[0]]>1) { "x]]>y" }'
    const out = parseXml(serializeXml(doc({ type: 'PowerShell', engine: 'pwsh', script })))
    const p = out.items[0].payload
    expect(p.type === 'PowerShell' && p.script).toBe(script)
  })
})

describe('#22 registry value whitespace', () => {
  it('keeps surrounding whitespace on string values through a round trip', () => {
    for (const registryType of ['String', 'ExpandString', 'MultiString']) {
      const out = parseXml(serializeXml(doc(reg({ registryType, value: '  padded \n' }))))
      const p = out.items[0].payload
      expect(p.type === 'Registry' && p.value).toBe('  padded \n')
    }
  })
  it('still trims numeric values', () => {
    const out = parseXml(file(`<Item><Name>I</Name><Type>Registry</Type><OS/><Registry><Hive>HKLM</Hive><Name>v</Name><Path>P</Path><Action>SetValue</Action><Value> 5
</Value><Type>DWord</Type></Registry></Item>`))
    const p = out.items[0].payload
    expect(p.type === 'Registry' && p.value).toBe('5')
  })
})
