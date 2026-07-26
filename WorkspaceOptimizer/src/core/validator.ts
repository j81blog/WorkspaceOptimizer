import type { TemplateDocument, ValidationResult, ValidationIssue, RegistryPayload, ServicePayload, ScheduledTaskPayload, FileFolderPayload } from './types'

const REG_ACTIONS = ['SetValue','DeleteKey','DeleteKeyRecursively','DeleteValue']
const REG_TYPES   = ['String','ExpandString','Binary','DWord','MultiString','Qword']
// Numeric/binary types need a value; the string types may legitimately be empty
// (setting a registry value to "" is a valid operation).
const REG_NEEDS_VALUE = ['dword','qword','binary']
const SVC_ACTIONS = ['Disabled','Automatic','Manual']
const ST_ACTIONS  = ['Enabled','Disabled']
const FF_ACTIONS  = ['Rename','Remove']
const FF_TYPES    = ['File','Folder']

export function validate(doc: TemplateDocument): ValidationResult {
  const errors: ValidationIssue[] = []
  const warnings: ValidationIssue[] = []
  const e = (code: string, path: string, message: string, itemId?: string) =>
    errors.push({ severity: 'Error', code, path, message, itemId })
  const w = (code: string, path: string, message: string, itemId?: string) =>
    warnings.push({ severity: 'Warning', code, path, message, itemId })

  if (doc.items.length === 0) w('STRUCT_ITEM_REQUIRED', '/Items', 'No items in template')

  // Template properties. These describe the file for a marketplace catalog, which
  // cannot be generated without them, so they block the download like any other error.
  // Id is auto-filled when the properties dialog opens, so it is only ever missing on a
  // document that has never been through it.
  for (const [field, label] of [['name', 'Name'], ['description', 'Description'], ['author', 'Author']] as const) {
    if (!doc.metadata?.[field]?.trim()) {
      e('META_REQUIRED', `/Metadata/${label}`, `Template ${label} is required. Set it in Template Properties`)
    }
  }

  const seenTags = new Set<string>()
  for (const os of doc.supportedOs) {
    if (!os.tag) { e('OS_TAG_REQUIRED', '/SupportedOS', 'OS entry has empty Tag'); continue }
    const tagLow = os.tag.toLowerCase()
    if (seenTags.has(tagLow)) e('OS_TAG_DUPLICATE', `/SupportedOS/${os.tag}`, `Duplicate OS tag: ${os.tag}`)
    seenTags.add(tagLow)
    if (os.buildStartsWith.length === 0) w('OS_BUILD_EMPTY', `/SupportedOS/${os.tag}`, `OS "${os.tag}" has no build prefixes`)
  }

  const knownTags = new Set(doc.supportedOs.filter(o => o.tag).map(o => o.tag.toLowerCase()))

  for (const item of doc.items) {
    const base = `/Item[${item.name || item.id}]`
    const id = item.id
    if (!item.name?.trim()) e('ITEM_NAME_REQUIRED', `${base}/Name`, 'Name is required', id)
    if (!item.category?.trim()) e('ITEM_CATEGORY_REQUIRED', `${base}/Category`, 'Category is required', id)
    if (!Number.isFinite(item.order) || item.order < 0 || item.order > 99999)
      e('ITEM_ORDER_RANGE', `${base}/Order`, `Order must be 0–99999 (got ${item.order})`, id)

    for (const [tag] of Object.entries(item.os)) {
      if (!knownTags.has(tag.toLowerCase()))
        e('OS_MAPPING_UNKNOWN_TAG', `${base}/OS/${tag}`, `OS tag "${tag}" not in SupportedOS`, id)
    }

    const p = item.payload
    switch (p.type) {
      case 'Registry':      validateRegistry(p, base, id, e); break
      case 'Service':       validateService(p, base, id, e); break
      case 'ScheduledTask': validateScheduledTask(p, base, id, e); break
      case 'StoreApp':      if (!p.name) e('FIELD_REQUIRED', `${base}/StoreApp/Name`, 'Name is required', id); break
      case 'PowerShell':    if (!p.script) e('FIELD_REQUIRED', `${base}/PowerShell/Script`, 'Script is required', id); break
      case 'FileFolder':    validateFileFolder(p, base, id, e); break
    }
  }
  return { errors, warnings }
}

function validateRegistry(r: RegistryPayload, base: string, id: string, e: (c:string,p:string,m:string,id?:string)=>void) {
  if (!r.path) e('FIELD_REQUIRED', `${base}/Registry/Path`, 'Path is required', id)
  if (!REG_ACTIONS.includes(r.action)) e('ENUM_INVALID', `${base}/Registry/Action`, `Invalid action: "${r.action}"`, id)
  if (['SetValue','DeleteValue'].includes(r.action) && !r.name)
    e('FIELD_REQUIRED', `${base}/Registry/Name`, `Name required for ${r.action}`, id)
  if (r.action === 'SetValue') {
    if (REG_NEEDS_VALUE.includes(r.registryType?.toLowerCase()) && !r.value && r.value !== '0')
      e('FIELD_REQUIRED', `${base}/Registry/Value`, `Value required for ${r.registryType}`, id)
    if (!REG_TYPES.find(t => t.toLowerCase() === r.registryType?.toLowerCase()))
      e('ENUM_INVALID', `${base}/Registry/Type`, `Invalid registry type: "${r.registryType}"`, id)
    const v = r.value?.trim()
    if (r.registryType?.toLowerCase() === 'dword' && v && !/^(0x[0-9a-fA-F]+|\d+)$/.test(v))
      e('FIELD_FORMAT', `${base}/Registry/Value`, 'DWord must be decimal or 0x hex', id)
    if (r.registryType?.toLowerCase() === 'qword' && v && !/^(0x[0-9a-fA-F]+|\d+)$/.test(v))
      e('FIELD_FORMAT', `${base}/Registry/Value`, 'Qword must be decimal or 0x hex', id)
    if (r.registryType?.toLowerCase() === 'binary' && v && !/^([0-9a-fA-F]{2}[\s,])*[0-9a-fA-F]{2}$/.test(v))
      e('FIELD_FORMAT', `${base}/Registry/Value`, 'Binary must be hex byte pairs', id)
  }
}

function validateService(s: ServicePayload, base: string, id: string, e: (c:string,p:string,m:string,id?:string)=>void) {
  if (!s.name) e('FIELD_REQUIRED', `${base}/Service/Name`, 'Name is required', id)
  if (!SVC_ACTIONS.includes(s.action)) e('ENUM_INVALID', `${base}/Service/Action`, `Invalid action: "${s.action}"`, id)
}

function validateScheduledTask(st: ScheduledTaskPayload, base: string, id: string, e: (c:string,p:string,m:string,id?:string)=>void) {
  if (!st.name) e('FIELD_REQUIRED', `${base}/ScheduledTask/Name`, 'Name is required', id)
  if (!st.path) e('FIELD_REQUIRED', `${base}/ScheduledTask/Path`, 'Path is required', id)
  if (!ST_ACTIONS.includes(st.action)) e('ENUM_INVALID', `${base}/ScheduledTask/Action`, `Invalid action: "${st.action}"`, id)
}

function validateFileFolder(ff: FileFolderPayload, base: string, id: string, e: (c:string,p:string,m:string,id?:string)=>void) {
  if (!ff.path) e('FIELD_REQUIRED', `${base}/FileFolder/Path`, 'Path is required', id)
  if (!FF_ACTIONS.includes(ff.action)) e('ENUM_INVALID', `${base}/FileFolder/Action`, `Invalid action: "${ff.action}"`, id)
  if (!FF_TYPES.includes(ff.itemType)) e('ENUM_INVALID', `${base}/FileFolder/ItemType`, `Invalid item type: "${ff.itemType}"`, id)
  if (ff.action === 'Rename' && !ff.newName) e('FIELD_REQUIRED', `${base}/FileFolder/NewName`, 'NewName required for Rename', id)
}
