import { describe, it, expect } from 'vitest'
import { parseReg, decodeRegBuffer, regEntriesToItems } from '../../src/core/regParser'
import { validate } from '../../src/core/validator'
import type { OsDefinition } from '../../src/core/types'

const HDR = 'Windows Registry Editor Version 5.00'
const W11: OsDefinition = { tag: 'Windows11', name: 'Windows 11', abbreviation: 'W11', isServerOs: false, buildStartsWith: ['22'] }

/** Build a .reg byte buffer in a given encoding, for the decode tests. */
function encode(text: string, enc: 'utf-16le' | 'utf-16be' | 'utf-8' | 'utf-8-bom' | 'utf-16le-nobom'): ArrayBuffer {
  if (enc === 'utf-8') return new TextEncoder().encode(text).buffer as ArrayBuffer
  if (enc === 'utf-8-bom') {
    const body = new TextEncoder().encode(text)
    const out = new Uint8Array(body.length + 3)
    out.set([0xef, 0xbb, 0xbf]); out.set(body, 3)
    return out.buffer
  }
  const be = enc === 'utf-16be'
  const withBom = enc !== 'utf-16le-nobom'
  const out = new Uint8Array(text.length * 2 + (withBom ? 2 : 0))
  let i = 0
  if (withBom) { out[i++] = be ? 0xfe : 0xff; out[i++] = be ? 0xff : 0xfe }
  for (const ch of text) {
    const c = ch.charCodeAt(0)
    if (be) { out[i++] = c >> 8; out[i++] = c & 0xff } else { out[i++] = c & 0xff; out[i++] = c >> 8 }
  }
  return out.buffer
}

describe('decodeRegBuffer', () => {
  it.each(['utf-16le', 'utf-16be', 'utf-8', 'utf-8-bom'] as const)('decodes %s', (enc) => {
    const { text, encoding } = decodeRegBuffer(encode(HDR, enc))
    expect(text).toBe(HDR)
    expect(encoding).toBe(enc)
  })

  it('detects BOM-less UTF-16LE from the NUL density', () => {
    const { text, encoding } = decodeRegBuffer(encode(HDR, 'utf-16le-nobom'))
    expect(encoding).toBe('utf-16le')
    expect(text).toBe(HDR)
  })

  it('does not mangle plain ASCII as UTF-16', () => {
    expect(decodeRegBuffer(encode('hello world', 'utf-8')).encoding).toBe('utf-8')
  })
})

describe('parseReg: headers', () => {
  it('recognizes the 5.00 header', () => {
    expect(parseReg(HDR).headerVersion).toBe('5.00')
  })

  it('recognizes REGEDIT4', () => {
    expect(parseReg('REGEDIT4').headerVersion).toBe('REGEDIT4')
  })

  it('warns but keeps parsing when the header is missing', () => {
    const r = parseReg('[HKEY_LOCAL_MACHINE\\SOFTWARE\\X]\n"A"="b"')
    expect(r.headerVersion).toBeNull()
    expect(r.warnings.some(w => w.code === 'MISSING_HEADER')).toBe(true)
    expect(r.entries).toHaveLength(1)
  })
})

describe('parseReg: hives', () => {
  const at = (key: string) => parseReg(`${HDR}\n[${key}]\n"V"="x"`).entries[0]

  it('maps long and short HKLM', () => {
    expect(at('HKEY_LOCAL_MACHINE\\SOFTWARE\\A')).toMatchObject({ hive: 'HKLM', path: 'SOFTWARE\\A' })
    expect(at('HKLM\\SOFTWARE\\A')).toMatchObject({ hive: 'HKLM', path: 'SOFTWARE\\A' })
  })

  it('maps HKCU and HKU', () => {
    expect(at('HKEY_CURRENT_USER\\Console')).toMatchObject({ hive: 'HKCU', path: 'Console' })
    expect(at('HKEY_USERS\\S-1-5-18\\X')).toMatchObject({ hive: 'HKU', path: 'S-1-5-18\\X' })
  })

  it('maps HKEY_USERS\\.DEFAULT to the DefaultUser hive', () => {
    expect(at('HKEY_USERS\\.DEFAULT\\Control Panel')).toMatchObject({
      hive: 'HKU\\DefaultUser', path: 'Control Panel'
    })
  })

  it('rewrites HKCR under HKLM\\SOFTWARE\\Classes and warns', () => {
    const r = parseReg(`${HDR}\n[HKEY_CLASSES_ROOT\\.txt]\n"V"="x"`)
    expect(r.entries[0]).toMatchObject({ hive: 'HKLM', path: 'SOFTWARE\\Classes\\.txt' })
    expect(r.warnings.some(w => w.code === 'HIVE_REWRITTEN')).toBe(true)
  })

  it('skips HKEY_CURRENT_CONFIG with a warning', () => {
    const r = parseReg(`${HDR}\n[HKEY_CURRENT_CONFIG\\X]\n"V"="x"`)
    expect(r.entries).toHaveLength(0)
    expect(r.warnings.some(w => w.code === 'UNSUPPORTED_HIVE')).toBe(true)
  })

  it('maps [-Key] to a recursive delete', () => {
    const r = parseReg(`${HDR}\n[-HKEY_CURRENT_USER\\Bad]`)
    expect(r.entries[0]).toMatchObject({ action: 'DeleteKeyRecursively', hive: 'HKCU', path: 'Bad' })
  })

  it('skips values under a deleted key', () => {
    const r = parseReg(`${HDR}\n[-HKCU\\Bad]\n"V"="x"`)
    expect(r.entries).toHaveLength(1)
    expect(r.warnings.some(w => w.code === 'VALUE_UNDER_DELETED_KEY')).toBe(true)
  })
})

describe('parseReg: value types', () => {
  const val = (rhs: string) => parseReg(`${HDR}\n[HKLM\\SW\\T]\n${rhs}`).entries[0]

  it('handles the default value via @', () => {
    expect(val('@="root"')).toMatchObject({ name: '', value: 'root', registryType: 'String' })
  })

  it('handles value deletion', () => {
    expect(val('"V"=-')).toMatchObject({ action: 'DeleteValue', name: 'V', value: '' })
  })

  it('unescapes backslashes and quotes in strings', () => {
    expect(val('"P"="C:\\\\Temp\\\\a \\"q\\" b"').value).toBe('C:\\Temp\\a "q" b')
  })

  it('converts dword to decimal', () => {
    expect(val('"D"=dword:0000001f')).toMatchObject({ registryType: 'DWord', value: '31' })
  })

  it('emits binary as comma-separated hex pairs', () => {
    expect(val('"B"=hex:de,ad,be,ef')).toMatchObject({ registryType: 'Binary', value: 'de,ad,be,ef' })
  })

  it('decodes hex(2) as ExpandString', () => {
    // "%TEMP%" in UTF-16LE with terminator
    expect(val('"E"=hex(2):25,00,54,00,45,00,4d,00,50,00,25,00,00,00')).toMatchObject({
      registryType: 'ExpandString', value: '%TEMP%'
    })
  })

  it('decodes hex(7) as newline-joined MultiString without trailing blanks', () => {
    // "a\0b\0\0"
    expect(val('"M"=hex(7):61,00,00,00,62,00,00,00,00,00')).toMatchObject({
      registryType: 'MultiString', value: 'a\nb'
    })
  })

  it('reads hex(4) little-endian', () => {
    expect(val('"L"=hex(4):01,00,00,00')).toMatchObject({ registryType: 'DWord', value: '1' })
  })

  it('reads hex(b) as Qword with full precision above 2^53', () => {
    // 0x0123456789ABCDEF = 81985529216486895, larger than Number.MAX_SAFE_INTEGER
    expect(val('"Q"=hex(b):ef,cd,ab,89,67,45,23,01')).toMatchObject({
      registryType: 'Qword', value: '81985529216486895'
    })
  })

  it('skips unsupported resource-list types', () => {
    const r = parseReg(`${HDR}\n[HKLM\\SW\\T]\n"R"=hex(a):00,01`)
    expect(r.entries).toHaveLength(0)
    expect(r.warnings.some(w => w.code === 'UNSUPPORTED_TYPE')).toBe(true)
  })

  it('skips malformed hex with a warning', () => {
    const r = parseReg(`${HDR}\n[HKLM\\SW\\T]\n"B"=hex:zz,01`)
    expect(r.entries).toHaveLength(0)
    expect(r.warnings.some(w => w.code === 'BAD_HEX')).toBe(true)
  })
})

describe('parseReg: line handling', () => {
  it('joins backslash continuations and reports the first physical line', () => {
    const src = `${HDR}\n[HKLM\\SW\\T]\n"B"=hex:00,01,\\\n  02,03,\\\n  04,05`
    const e = parseReg(src).entries[0]
    expect(e.value).toBe('00,01,02,03,04,05')
    expect(e.line).toBe(3)
  })

  it('ignores comment lines', () => {
    const r = parseReg(`${HDR}\n; a comment\n[HKLM\\SW\\T]\n"V"="x"`)
    expect(r.entries).toHaveLength(1)
  })

  it('keeps a semicolon inside a quoted value', () => {
    expect(parseReg(`${HDR}\n[HKLM\\SW\\T]\n"V"="a;b"`).entries[0].value).toBe('a;b')
  })

  it('warns on a value before any key', () => {
    const r = parseReg(`${HDR}\n"V"="x"`)
    expect(r.entries).toHaveLength(0)
    expect(r.warnings.some(w => w.code === 'NO_SECTION')).toBe(true)
  })

  it('keeps going after a garbage line', () => {
    const r = parseReg(`${HDR}\n[HKLM\\SW\\T]\n!!! nonsense !!!\n"V"="x"`)
    expect(r.entries).toHaveLength(1)
    expect(r.warnings.some(w => w.code === 'UNPARSEABLE_LINE')).toBe(true)
  })

  it('handles an empty file without throwing', () => {
    expect(parseReg('').entries).toHaveLength(0)
  })

  it('handles CRLF line endings', () => {
    expect(parseReg(`${HDR}\r\n[HKLM\\SW\\T]\r\n"V"="x"\r\n`).entries).toHaveLength(1)
  })
})

describe('regEntriesToItems', () => {
  const defaults = {
    category: 'Imported',
    order: 100,
    os: { Windows11: { execute: true, physical: true, virtual: true } }
  }

  it('produces items that pass validation', () => {
    const src = [
      HDR,
      '[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Test]',
      '"AllowTelemetry"=dword:00000000',
      '"Path"="C:\\\\Temp"',
      '"Empty"=""',
      '"Gone"=-',
      '[-HKEY_CURRENT_USER\\Software\\Junk]'
    ].join('\n')
    const { entries } = parseReg(src)
    const items = regEntriesToItems(entries, defaults, 'tweaks.reg')

    expect(items).toHaveLength(5)
    const result = validate({ metadata: { version: '1', schemaVersion: '1', id: 'x', name: 'N', description: 'D', author: 'A', category: '', tags: [] }, supportedOs: [W11], items })
    expect(result.errors).toHaveLength(0)
  })

  it('derives a non-empty name and a provenance description', () => {
    const { entries } = parseReg(`${HDR}\n[HKLM\\SOFTWARE\\A\\Advanced]\n"HideFileExt"=dword:00000001`)
    const item = regEntriesToItems(entries, defaults, 'tweaks.reg')[0]
    expect(item.name).toBe('SetValue Advanced\\HideFileExt')
    expect(item.description).toContain('tweaks.reg')
  })

  it('does not share OS mapping objects between items', () => {
    const { entries } = parseReg(`${HDR}\n[HKLM\\SW\\T]\n"A"="1"\n"B"="2"`)
    const items = regEntriesToItems(entries, defaults, 'f.reg')
    items[0].os.Windows11.execute = false
    expect(items[1].os.Windows11.execute).toBe(true)
  })
})
