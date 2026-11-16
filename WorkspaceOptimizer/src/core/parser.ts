import type {
  TemplateDocument, TemplateMetadata, OsDefinition, TemplateItem, OsMapping,
  ItemPayload, ItemType,
  RegistryPayload, ServicePayload, ScheduledTaskPayload,
  StoreAppPayload, PowerShellPayload, FileFolderPayload
} from './types'

export function parseXml(xmlString: string): TemplateDocument {
  const doc = new DOMParser().parseFromString(xmlString, 'application/xml')
  const err = doc.querySelector('parsererror')
  if (err) throw new Error('XML parse error: ' + (err.textContent ?? '').slice(0, 300))
  const metadata = parseMetadata(doc)
  return {
    metadata,
    supportedOs: parseSupportedOs(doc),
    items: parseItems(doc, metadata?.category)
  }
}

function parseMetadata(doc: Document): TemplateMetadata | null {
  const el = doc.querySelector('Items > Metadata')
  // No block at all stays null, so serializing a file that never had one does not
  // invent it. The Properties dialog fills one in on first use.
  if (!el) return null
  return {
    version: text(el, 'Version'),
    schemaVersion: text(el, 'SchemaVersion'),
    id: text(el, 'Id'),
    name: text(el, 'Name'),
    description: text(el, 'Description'),
    author: text(el, 'Author'),
    category: text(el, 'Category'),
    tags: Array.from(el.querySelectorAll('Tags > Tag'))
      .map(t => t.textContent?.trim() ?? '')
      .filter(Boolean)
  }
}

function parseSupportedOs(doc: Document): OsDefinition[] {
  return Array.from(doc.querySelectorAll('SupportedOS > OS')).map(el => ({
    tag: text(el, 'Tag'),
    name: text(el, 'Name'),
    abbreviation: text(el, 'Abbreviation'),
    isServerOs: text(el, 'ServerOS') === '1',
    buildStartsWith: Array.from(el.querySelectorAll('BuildStartsWith'))
      .map(b => b.textContent?.trim() ?? '')
      .filter(Boolean)
  }))
}

/** Category the validator requires when neither the item nor the file supplies one. */
export const DEFAULT_CATEGORY = 'Imported'

/**
 * @param fallbackCategory the file's `<Metadata><Category>`, used for items that do not
 *   name their own. Category is required by the validator, so it always ends up set.
 */
function parseItems(doc: Document, fallbackCategory = ''): TemplateItem[] {
  return Array.from(doc.querySelectorAll('Items > Item')).map(el => {
    const typeRaw = text(el, 'Type')
    const type = resolveType(typeRaw)
    return {
      id: crypto.randomUUID(),
      name: text(el, 'Name'),
      description: text(el, 'Description'),
      type,
      typeRaw,
      // Item's own category, else the file's, else a placeholder.
      category: text(el, 'Category') || fallbackCategory || DEFAULT_CATEGORY,
      order: parseOrder(text(el, 'Order')),
      os: parseOsMappings(el),
      payload: parsePayload(el, type)
    }
  })
}

function text(el: Element, tag: string): string {
  return el.querySelector(tag)?.textContent?.trim() ?? ''
}

function resolveType(raw: string): ItemType {
  const lower = raw.toLowerCase()
  const map: Record<string, ItemType> = {
    registry: 'Registry',
    service: 'Service',
    scheduledtask: 'ScheduledTask',
    storeapp: 'StoreApp',
    powershell: 'PowerShell',
    filefolder: 'FileFolder'
  }
  return map[lower] ?? 'Unknown'
}

function parseOrder(raw: string): number {
  if (!raw) return 100
  const n = parseInt(raw, 10)
  return isNaN(n) ? 100 : n
}

function parseOsMappings(item: Element): Record<string, OsMapping> {
  const osEl = item.querySelector('OS')
  if (!osEl) return {}
  const result: Record<string, OsMapping> = {}
  for (const child of Array.from(osEl.children)) {
    result[child.tagName] = {
      execute: child.querySelector('Execute')?.textContent?.trim() === '1',
      physical: child.querySelector('Physical')?.textContent?.trim() === '1',
      virtual: child.querySelector('Virtual')?.textContent?.trim() === '1'
    }
  }
  return result
}

function parsePayload(el: Element, type: ItemType): ItemPayload {
  switch (type) {
    case 'Registry':      return parseRegistry(el)
    case 'Service':       return parseService(el)
    case 'ScheduledTask': return parseScheduledTask(el)
    case 'StoreApp':      return parseStoreApp(el)
    case 'PowerShell':    return parsePowerShell(el)
    case 'FileFolder':    return parseFileFolder(el)
    default:              return { type: 'Unknown', rawXml: unrecognizedXml(el) }
  }
}

const ITEM_CHILDREN = ['Name', 'Description', 'Type', 'Category', 'Order', 'OS']

/** Everything under an Item besides the fields this editor owns, so it can be written back unchanged. */
function unrecognizedXml(item: Element): string {
  const serializer = new XMLSerializer()
  return Array.from(item.children)
    .filter(c => !ITEM_CHILDREN.includes(c.tagName))
    .map(c => serializer.serializeToString(c))
    .join('\n')
}

const STRING_REG_TYPES = ['string', 'expandstring', 'multistring']

/** String values are data, so their leading and trailing whitespace is significant. */
export function keepsWhitespace(registryType: string): boolean {
  return STRING_REG_TYPES.includes(registryType.toLowerCase())
}

function normalizeRegistryType(raw: string): string {
  const map: Record<string, string> = {
    dword: 'DWord', string: 'String', expandstring: 'ExpandString',
    multistring: 'MultiString', qword: 'Qword', binary: 'Binary'
  }
  return map[raw.toLowerCase()] ?? raw
}

function normalizeHive(raw: string): string {
  const map: Record<string, string> = {
    hklm: 'HKLM', hkcu: 'HKCU', hku: 'HKU', 'hku\\defaultuser': 'HKU\\DefaultUser'
  }
  return map[raw.toLowerCase()] ?? raw
}

function parseRegistry(el: Element): RegistryPayload {
  const r = el.querySelector('Registry')
  if (!r) return { type: 'Registry', hive: 'HKLM', path: '', name: '', action: 'SetValue', value: '', registryType: 'DWord' }
  let action = text(r, 'Action') || 'SetValue'
  const name = text(r, 'Name')
  // Legacy "Delete" migration
  if (action.toLowerCase() === 'delete') action = name === '' ? 'DeleteKey' : 'DeleteValue'
  const registryType = normalizeRegistryType(text(r, 'Type'))
  const rawValue = r.querySelector('Value')?.textContent ?? ''
  return {
    type: 'Registry',
    hive: normalizeHive(text(r, 'Hive')) || 'HKLM',
    path: text(r, 'Path'),
    name,
    action,
    value: keepsWhitespace(registryType) ? rawValue : rawValue.trim(),
    registryType
  }
}

function parseService(el: Element): ServicePayload {
  const s = el.querySelector('Service')
  if (!s) return { type: 'Service', name: '', action: 'Disabled' }
  return { type: 'Service', name: text(s, 'Name'), action: text(s, 'Action') || 'Disabled' }
}

function parseScheduledTask(el: Element): ScheduledTaskPayload {
  const st = el.querySelector('ScheduledTask')
  if (!st) return { type: 'ScheduledTask', name: '', path: '', action: 'Disabled' }
  return { type: 'ScheduledTask', name: text(st, 'Name'), path: text(st, 'Path'), action: text(st, 'Action') || 'Disabled' }
}

function parseStoreApp(el: Element): StoreAppPayload {
  const sa = el.querySelector('StoreApp')
  return { type: 'StoreApp', name: sa ? text(sa, 'Name') : '' }
}

function parsePowerShell(el: Element): PowerShellPayload {
  const ps = el.querySelector('PowerShell')
  if (!ps) return { type: 'PowerShell', engine: 'powershell', script: '' }
  const scriptEl = ps.querySelector('Script')
  return {
    type: 'PowerShell',
    engine: text(ps, 'Engine') || 'powershell',
    script: scriptEl?.textContent ?? ''
  }
}

function parseFileFolder(el: Element): FileFolderPayload {
  const ff = el.querySelector('FileFolder')
  if (!ff) return { type: 'FileFolder', path: '', action: 'Remove', itemType: 'File', newName: '' }
  return {
    type: 'FileFolder',
    path: text(ff, 'Path'),
    action: text(ff, 'Action') || 'Remove',
    itemType: text(ff, 'ItemType') || 'File',
    newName: text(ff, 'NewName')
  }
}

const KNOWN_CHILDREN: Record<string, string[]> = {
  Items: ['Metadata', 'SupportedOS', 'Item'],
  Metadata: ['Version', 'SchemaVersion', 'Id', 'Name', 'Description', 'Author', 'Category', 'Tags'],
  Tags: ['Tag'],
  SupportedOS: ['OS'],
  OS: ['Tag', 'Name', 'Abbreviation', 'ServerOS', 'Builds'],
  Builds: ['BuildStartsWith'],
  Item: [...ITEM_CHILDREN, 'Registry', 'Service', 'ScheduledTask', 'StoreApp', 'PowerShell', 'FileFolder'],
  Registry: ['Hive', 'Name', 'Path', 'Action', 'Value', 'Type'],
  Service: ['Name', 'Action'],
  ScheduledTask: ['Name', 'Path', 'Action'],
  StoreApp: ['Name'],
  PowerShell: ['Engine', 'Script'],
  FileFolder: ['Path', 'Action', 'ItemType', 'NewName']
}

/**
 * Content in an XML file that parsing and re-saving would silently drop: comments and
 * elements the editor has no field for. Unrecognized item types are not listed because
 * they are kept verbatim.
 */
export function findDroppedContent(xmlString: string): string[] {
  const doc = new DOMParser().parseFromString(xmlString, 'application/xml')
  if (doc.querySelector('parsererror') || !doc.documentElement) return []
  const found: string[] = []

  let comments = 0
  const walker = doc.createTreeWalker(doc, 0x80 /* NodeFilter.SHOW_COMMENT */)
  while (walker.nextNode()) comments++
  if (comments) found.push(`${comments} XML comment${comments === 1 ? '' : 's'}`)

  const visit = (el: Element, where: string) => {
    // An Item's children under <OS> are OS tags, which can be anything.
    if (el.tagName === 'OS' && el.parentElement?.tagName === 'Item') {
      for (const tagEl of Array.from(el.children)) {
        for (const c of Array.from(tagEl.children)) {
          if (!['Execute', 'Physical', 'Virtual'].includes(c.tagName)) found.push(`<${c.tagName}> in ${where}`)
        }
      }
      return
    }
    const known = KNOWN_CHILDREN[el.tagName]
    if (!known) return
    const isUnknownItem = el.tagName === 'Item' &&
      resolveType(el.querySelector('Type')?.textContent?.trim() ?? '') === 'Unknown'
    for (const c of Array.from(el.children)) {
      if (!known.includes(c.tagName)) {
        if (!isUnknownItem) found.push(`<${c.tagName}> in ${where}`)
        continue
      }
      const label = c.tagName === 'Item'
        ? `item "${c.querySelector('Name')?.textContent?.trim() || '(unnamed)'}"`
        : c.tagName === 'OS' ? `OS "${c.querySelector('Tag')?.textContent?.trim() ?? ''}"` : where
      visit(c, label)
    }
  }
  visit(doc.documentElement, 'the file')
  return found
}
