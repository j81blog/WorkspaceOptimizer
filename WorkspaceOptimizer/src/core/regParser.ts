import type { TemplateItem, OsMapping } from './types'

/**
 * Parser for Windows .reg files.
 *
 * Handles both `Windows Registry Editor Version 5.00` and the older `REGEDIT4`,
 * every REG_* value type regedit can emit, backslash line continuations, and the
 * UTF-16LE encoding regedit actually writes.
 *
 * Nothing here throws: unparseable input becomes a warning so a single bad line
 * never costs the user the rest of the file.
 */

export interface RegParseWarning {
  line: number
  code: string
  message: string
  raw: string
}

export interface RegParseEntry {
  hive: string          // HKLM | HKCU | HKU | HKU\DefaultUser
  path: string
  name: string          // '' for the key's default value
  action: 'SetValue' | 'DeleteKeyRecursively' | 'DeleteValue'
  value: string
  registryType: string
  line: number
}

export type RegEncoding = 'utf-16le' | 'utf-16be' | 'utf-8' | 'utf-8-bom'

export interface RegParseResult {
  entries: RegParseEntry[]
  warnings: RegParseWarning[]
  encoding: RegEncoding
  headerVersion: '5.00' | 'REGEDIT4' | null
}

/** Reject anything larger than this outright. See also MAX_REG_ENTRIES. */
export const MAX_REG_BYTES = 5 * 1024 * 1024
/** A review table beyond this size is unusable, and so is hand-reviewing it. */
export const MAX_REG_ENTRIES = 2000

// ── Decoding ──────────────────────────────────────────────────────────────────

/**
 * Detect the encoding from the BOM and decode. Regedit writes UTF-16LE, which
 * FileReader.readAsText would mangle into NUL-interleaved garbage, so callers must
 * read the file as an ArrayBuffer and come through here.
 */
export function decodeRegBuffer(buf: ArrayBuffer): { text: string; encoding: RegEncoding } {
  const b = new Uint8Array(buf)
  if (b.length >= 2 && b[0] === 0xff && b[1] === 0xfe) {
    return { text: new TextDecoder('utf-16le').decode(b.subarray(2)), encoding: 'utf-16le' }
  }
  if (b.length >= 2 && b[0] === 0xfe && b[1] === 0xff) {
    return { text: new TextDecoder('utf-16be').decode(b.subarray(2)), encoding: 'utf-16be' }
  }
  if (b.length >= 3 && b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) {
    return { text: new TextDecoder('utf-8').decode(b.subarray(3)), encoding: 'utf-8-bom' }
  }
  // Some tools strip the BOM. A high proportion of NUL bytes still means UTF-16LE.
  const probe = b.subarray(0, Math.min(512, b.length))
  const nuls = probe.reduce((n, byte) => n + (byte === 0 ? 1 : 0), 0)
  if (probe.length > 0 && nuls / probe.length > 0.25) {
    return { text: new TextDecoder('utf-16le').decode(b), encoding: 'utf-16le' }
  }
  return { text: new TextDecoder('utf-8').decode(b), encoding: 'utf-8' }
}

export function parseRegBuffer(buf: ArrayBuffer): RegParseResult {
  const { text, encoding } = decodeRegBuffer(buf)
  return { ...parseReg(text), encoding }
}

// ── Hive mapping ──────────────────────────────────────────────────────────────

interface HiveResult {
  hive: string
  pathPrefix: string
  note?: string
}

function mapHive(raw: string, rest: string): HiveResult | null {
  const h = raw.toUpperCase()
  if (h === 'HKEY_LOCAL_MACHINE' || h === 'HKLM') return { hive: 'HKLM', pathPrefix: '' }
  if (h === 'HKEY_CURRENT_USER' || h === 'HKCU') return { hive: 'HKCU', pathPrefix: '' }
  if (h === 'HKEY_USERS' || h === 'HKU') {
    // HKEY_USERS\.DEFAULT maps to the app's dedicated default-user hive.
    if (/^\.DEFAULT(\\|$)/i.test(rest)) {
      return { hive: 'HKU\\DefaultUser', pathPrefix: '', note: 'DEFAULT_USER' }
    }
    return { hive: 'HKU', pathPrefix: '' }
  }
  if (h === 'HKEY_CLASSES_ROOT' || h === 'HKCR') {
    // HKCR is a merged view; the machine-wide half is what a deployment template means.
    return { hive: 'HKLM', pathPrefix: 'SOFTWARE\\Classes\\', note: 'HKCR_REWRITE' }
  }
  return null
}

// ── Hex helpers ───────────────────────────────────────────────────────────────

function parseHexBytes(raw: string): number[] | null {
  const out: number[] = []
  for (const tok of raw.split(',')) {
    const t = tok.trim()
    if (!t) continue                       // trailing comma before a continuation
    if (!/^[0-9a-fA-F]{1,2}$/.test(t)) return null
    out.push(parseInt(t, 16))
  }
  return out
}

/** Decode UTF-16LE bytes and drop the trailing NUL terminator regedit writes. */
function decodeUtf16(bytes: number[]): string {
  const buf = new Uint8Array(bytes)
  return new TextDecoder('utf-16le').decode(buf).replace(/\0+$/, '')
}

function bytesToHexString(bytes: number[]): string {
  return bytes.map(b => b.toString(16).padStart(2, '0')).join(',')
}

// ── Parsing ───────────────────────────────────────────────────────────────────

interface LogicalLine {
  text: string
  line: number
}

/** Join backslash continuations, keeping the first physical line number. */
function toLogicalLines(text: string): LogicalLine[] {
  const physical = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')
  const out: LogicalLine[] = []
  let buffer: string | null = null
  let startLine = 0

  for (let i = 0; i < physical.length; i++) {
    const trimmed = physical[i].trim()
    const continues = trimmed.endsWith('\\')
    const body = continues ? trimmed.slice(0, -1) : trimmed

    if (buffer === null) {
      buffer = body
      startLine = i + 1
    } else {
      buffer += body
    }

    if (!continues) {
      out.push({ text: buffer, line: startLine })
      buffer = null
    }
  }
  if (buffer !== null) out.push({ text: buffer, line: startLine })
  return out
}

function unescapeRegString(s: string): string {
  return s.replace(/\\(.)/g, (_, c) => (c === '\\' || c === '"' ? c : '\\' + c))
}

export function parseReg(text: string): Omit<RegParseResult, 'encoding'> {
  const entries: RegParseEntry[] = []
  const warnings: RegParseWarning[] = []
  const warn = (line: number, code: string, message: string, raw: string) =>
    warnings.push({ line, code, message, raw: raw.slice(0, 120) })

  let headerVersion: RegParseResult['headerVersion'] = null
  let sawHeader = false
  let hive: string | null = null
  let basePath = ''
  let sectionDeleted = false

  for (const { text: raw, line } of toLogicalLines(text)) {
    const t = raw.trim()
    if (!t || t.startsWith(';')) continue

    if (!sawHeader) {
      sawHeader = true
      if (/^Windows Registry Editor Version 5\.00$/i.test(t)) { headerVersion = '5.00'; continue }
      if (/^REGEDIT4$/i.test(t)) { headerVersion = 'REGEDIT4'; continue }
      warn(line, 'MISSING_HEADER', 'File does not start with a recognized .reg header', t)
      // fall through, hand-written snippets often omit it
    }

    // Section header
    const section = t.match(/^\[(-?)(.+)\]$/)
    if (section) {
      const isDelete = section[1] === '-'
      const full = section[2].trim()
      const sep = full.indexOf('\\')
      const hivePart = sep === -1 ? full : full.slice(0, sep)
      let rest = sep === -1 ? '' : full.slice(sep + 1)

      const mapped = mapHive(hivePart, rest)
      if (!mapped) {
        warn(line, 'UNSUPPORTED_HIVE', `Unsupported hive "${hivePart}", key skipped`, t)
        hive = null
        sectionDeleted = false
        continue
      }
      if (mapped.note === 'DEFAULT_USER') rest = rest.replace(/^\.DEFAULT\\?/i, '')
      if (mapped.note === 'HKCR_REWRITE') {
        warn(line, 'HIVE_REWRITTEN', `${hivePart} mapped to HKLM\\SOFTWARE\\Classes`, t)
      }

      hive = mapped.hive
      basePath = (mapped.pathPrefix + rest).replace(/\\+/g, '\\').replace(/^\\|\\$/g, '')
      sectionDeleted = isDelete

      if (isDelete) {
        // regedit's [-Key] removes the key and everything under it.
        entries.push({
          hive, path: basePath, name: '', action: 'DeleteKeyRecursively',
          value: '', registryType: 'String', line
        })
      }
      continue
    }

    // Value line
    const value = t.match(/^("(?:[^"\\]|\\.)*"|@)\s*=\s*([\s\S]*)$/)
    if (!value) {
      warn(line, 'UNPARSEABLE_LINE', 'Line is neither a key nor a value assignment', t)
      continue
    }
    if (hive === null) {
      warn(line, 'NO_SECTION', 'Value appears before any key, skipped', t)
      continue
    }
    if (sectionDeleted) {
      warn(line, 'VALUE_UNDER_DELETED_KEY', 'Value under a deleted key, skipped', t)
      continue
    }

    const name = value[1] === '@' ? '' : unescapeRegString(value[1].slice(1, -1))
    const rhs = value[2].trim()
    const push = (action: RegParseEntry['action'], registryType: string, v: string) =>
      entries.push({ hive: hive!, path: basePath, name, action, value: v, registryType, line })

    if (rhs === '-') { push('DeleteValue', 'String', ''); continue }

    if (rhs.startsWith('"')) {
      const m = rhs.match(/^"((?:[^"\\]|\\.)*)"$/)
      if (!m) { warn(line, 'UNPARSEABLE_VALUE', 'Malformed string value', t); continue }
      push('SetValue', 'String', unescapeRegString(m[1]))
      continue
    }

    const dword = rhs.match(/^dword:\s*([0-9a-fA-F]+)$/i)
    if (dword) { push('SetValue', 'DWord', String(parseInt(dword[1], 16))); continue }

    const hex = rhs.match(/^hex(?:\(([0-9a-fA-F]+)\))?:\s*(.*)$/i)
    if (hex) {
      const sub = (hex[1] ?? '3').toLowerCase()
      const bytes = parseHexBytes(hex[2])
      if (bytes === null) { warn(line, 'BAD_HEX', 'Malformed hex byte list', t); continue }

      switch (sub) {
        case '0':
          warn(line, 'TYPE_APPROXIMATED', 'REG_NONE imported as Binary', t)
          push('SetValue', 'Binary', bytesToHexString(bytes)); break
        case '1':
          push('SetValue', 'String', decodeUtf16(bytes)); break
        case '2':
          push('SetValue', 'ExpandString', decodeUtf16(bytes)); break
        case '3':
          push('SetValue', 'Binary', bytesToHexString(bytes)); break
        case '4':
          push('SetValue', 'DWord', String(leToNumber(bytes.slice(0, 4)))); break
        case '5':
          warn(line, 'TYPE_APPROXIMATED', 'REG_DWORD_BIG_ENDIAN converted to DWord', t)
          push('SetValue', 'DWord', String(leToNumber(bytes.slice(0, 4).reverse()))); break
        case '7': {
          const parts = decodeUtf16(bytes).split('\0')
          while (parts.length && parts[parts.length - 1] === '') parts.pop()
          push('SetValue', 'MultiString', parts.join('\n')); break
        }
        case 'b':
          push('SetValue', 'Qword', leToBigInt(bytes.slice(0, 8)).toString()); break
        default:
          warn(line, 'UNSUPPORTED_TYPE', `REG type hex(${sub}) is not supported, skipped`, t)
      }
      continue
    }

    warn(line, 'UNPARSEABLE_VALUE', 'Unrecognized value format', t)
  }

  return { entries, warnings, headerVersion }
}

function leToNumber(bytes: number[]): number {
  let n = 0
  for (let i = bytes.length - 1; i >= 0; i--) n = n * 256 + bytes[i]
  return n
}

function leToBigInt(bytes: number[]): bigint {
  let n = 0n
  for (let i = bytes.length - 1; i >= 0; i--) n = n * 256n + BigInt(bytes[i])
  return n
}

// ── Conversion to template items ──────────────────────────────────────────────

export interface RegImportDefaults {
  category: string
  order: number
  os: Record<string, OsMapping>
}

function lastSegment(path: string): string {
  const parts = path.split('\\').filter(Boolean)
  return parts[parts.length - 1] ?? path
}

/** Human-readable item name, e.g. "SetValue Advanced\HideFileExt". */
function deriveName(e: RegParseEntry): string {
  const target = e.action === 'DeleteKeyRecursively'
    ? lastSegment(e.path)
    : `${lastSegment(e.path)}\\${e.name || '(default)'}`
  return `${e.action} ${target}`.slice(0, 80)
}

export function regEntriesToItems(
  entries: RegParseEntry[],
  defaults: RegImportDefaults,
  filename: string
): TemplateItem[] {
  return entries.map(e => ({
    id: crypto.randomUUID(),
    name: deriveName(e),
    description: `Imported from ${filename} (line ${e.line})`,
    type: 'Registry' as const,
    typeRaw: 'Registry',
    category: defaults.category,
    order: defaults.order,
    os: JSON.parse(JSON.stringify(defaults.os)),
    payload: {
      type: 'Registry' as const,
      hive: e.hive,
      path: e.path,
      name: e.name,
      action: e.action,
      value: e.value,
      registryType: e.registryType
    }
  }))
}
