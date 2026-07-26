// ── OS Definition (SupportedOS entry) ────────────────────────────────────────
export interface OsDefinition {
  tag: string             // unique XML element name e.g. "Windows11"
  name: string            // display name e.g. "Windows 11"
  abbreviation: string    // short label e.g. "W11"
  isServerOs: boolean
  buildStartsWith: string[]
}

// ── OS Mapping per item ───────────────────────────────────────────────────────
// Constraint: if physical=false AND virtual=false then execute must be false.
// Presence of key in TemplateItem.os means "supported". Absent key = not supported.
export interface OsMapping {
  execute: boolean
  physical: boolean
  virtual: boolean
}

// ── Metadata (optional <Metadata> block) ──────────────────────────────────────
/**
 * Descriptive fields live in the file itself so a template or snippet is
 * self-describing: a marketplace catalog can be generated from the files rather than
 * restating everything by hand. All are optional; the deploy script ignores this block.
 */
export interface TemplateMetadata {
  version: string         // build stamp, e.g. "2026.429.2230"
  schemaVersion: string   // format version, e.g. "1"
  id: string              // stable identifier, a GUID for generated files
  name: string            // display name
  description: string
  author: string
  category: string
  tags: string[]
}

// ── Template Document (root) ──────────────────────────────────────────────────
export interface TemplateDocument {
  metadata: TemplateMetadata | null   // null when the file carries no <Metadata>
  supportedOs: OsDefinition[]
  items: TemplateItem[]
}

// ── Item ──────────────────────────────────────────────────────────────────────
export interface TemplateItem {
  id: string              // internal UUID, never written to XML
  name: string
  description: string
  type: ItemType
  typeRaw: string         // original casing from XML, used in serialization
  category: string
  order: number           // 0–99999, default 100
  os: Record<string, OsMapping>   // key = OsDefinition.tag
  payload: ItemPayload
}

export type ItemType =
  | 'Registry'
  | 'Service'
  | 'ScheduledTask'
  | 'StoreApp'
  | 'PowerShell'
  | 'FileFolder'
  | 'Unknown'

// ── Payloads ──────────────────────────────────────────────────────────────────
export interface RegistryPayload {
  type: 'Registry'
  hive: string            // HKLM | HKCU | HKU | HKU\DefaultUser
  path: string
  name: string            // value name; empty string = default value
  action: string          // SetValue | DeleteKey | DeleteKeyRecursively | DeleteValue
  value: string
  registryType: string    // String | ExpandString | Binary | DWord | MultiString | Qword
}

export interface ServicePayload {
  type: 'Service'
  name: string
  action: string          // Disabled | Automatic | Manual
}

export interface ScheduledTaskPayload {
  type: 'ScheduledTask'
  name: string
  path: string
  action: string          // Enabled | Disabled
}

export interface StoreAppPayload {
  type: 'StoreApp'
  name: string
}

export interface PowerShellPayload {
  type: 'PowerShell'
  engine: string          // powershell | pwsh
  script: string
}

export interface FileFolderPayload {
  type: 'FileFolder'
  path: string
  action: string          // Delete | Rename | Remove
  itemType: string        // File | Folder
  newName: string         // required when action=Rename
}

export interface UnknownPayload {
  type: 'Unknown'
}

export type ItemPayload =
  | RegistryPayload
  | ServicePayload
  | ScheduledTaskPayload
  | StoreAppPayload
  | PowerShellPayload
  | FileFolderPayload
  | UnknownPayload

// ── Import / provenance ───────────────────────────────────────────────────────
export type ImportSourceKind = 'marketplace' | 'reg'

export interface ImportSource {
  id: string              // 'mp:wo.telemetry.off' | 'reg:tweaks.reg#1'
  kind: ImportSourceKind
  label: string           // "Disable Telemetry" | "tweaks.reg"
  origin: string          // "raw.githubusercontent.com"; empty for local files
}

export type MergeStatus = 'new' | 'duplicate' | 'conflict'

// ── Validation ────────────────────────────────────────────────────────────────
export type Severity = 'Error' | 'Warning'

export interface ValidationIssue {
  severity: Severity
  code: string
  path: string
  message: string
  itemId?: string
}

export interface ValidationResult {
  errors: ValidationIssue[]
  warnings: ValidationIssue[]
}

// ── UI state types ────────────────────────────────────────────────────────────
export type ViewMode = 'category' | 'order'
export type SortDir = 'asc' | 'desc'

export interface UiFilters {
  search: string
  category: string
  type: string
  os: string
}
