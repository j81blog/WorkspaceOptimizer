/**
 * Summarize what a marketplace submission actually does, for a human reviewer.
 *
 *   npm run review:submission              every file under public/marketplace/
 *   npm run review:submission -- a.xml b.xml   only these
 *
 * This is a REVIEW AID, not a gate. Deleting files, disabling services and running
 * PowerShell are all legitimate in an optimization template, so nothing here is
 * auto-rejected. The job is to make a reviewer read the parts that carry risk instead of
 * skimming a 200-line diff.
 *
 * Exits non-zero only on a structurally broken file. validate-catalog.mjs owns the
 * catalog rules, and this owns "what would this do to a machine".
 */
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve, join } from 'node:path'
import { discoverFiles, readXmlFile, relPath } from './catalog-lib.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const MARKETPLACE = join(root, 'public/marketplace')

/**
 * Things a reviewer should look at directly. Each is legitimate in some template, so
 * these are prompts, not verdicts.
 */
const SCRIPT_PATTERNS = [
  [/\b(iwr|irm|Invoke-WebRequest|Invoke-RestMethod|curl|wget)\b/i, 'downloads from the network'],
  [/\b(iex|Invoke-Expression)\b/i,                                 'executes a string as code'],
  [/\[System\.Reflection\.Assembly\]|Add-Type\s+-TypeDefinition/i,  'loads or compiles code at runtime'],
  [/FromBase64String|-enc(odedcommand)?\b/i,                        'runs base64-encoded content'],
  [/\bStart-Process\b/i,                                            'starts another process'],
  [/\bNew-Object\s+Net\.WebClient/i,                                'opens a network client'],
  [/\b(Remove-Item|rd|rmdir|del)\b.*-Recurse/i,                     'recursively deletes'],
  [/\bSet-ExecutionPolicy\b/i,                                      'changes the execution policy'],
  [/\bschtasks|Register-ScheduledTask\b/i,                          'creates a scheduled task'],
  [/\bNet\s+user\b|New-LocalUser/i,                                 'touches local accounts'],
]

/** Paths where a delete or rename is worth a second look. */
const SENSITIVE_PATHS = [
  /^[A-Z]:\\Windows(\\|$)/i,
  /^[A-Z]:\\Program Files( \(x86\))?(\\|$)/i,
  /^[A-Z]:\\Users(\\|$)/i,
  /^[A-Z]:\\?$/i,
]

/** Registry locations that affect the whole machine or its security posture. */
const SENSITIVE_KEYS = [
  [/SOFTWARE\\Policies/i,                         'group policy'],
  [/SYSTEM\\CurrentControlSet\\Services/i,        'service configuration'],
  [/Microsoft\\Windows Defender/i,                'Defender'],
  [/Microsoft\\Windows\\CurrentVersion\\Run/i,    'startup programs'],
  [/SAM|SECURITY\\Policy/i,                       'security database'],
  [/Winlogon|Authentication/i,                    'logon and authentication'],
]

const args = process.argv.slice(2).filter(a => !a.startsWith('-'))
const files = args.length
  ? args.map(a => {
      const abs = resolve(process.cwd(), a)
      // Show a path relative to the marketplace when the file lives there, otherwise the
      // one the caller typed, since a chain of ../ helps nobody.
      const rel = relPath(MARKETPLACE, abs)
      return {
        kind: abs.includes('template') ? 'template' : 'snippet',
        url: rel.startsWith('..') ? a : rel,
        absPath: abs
      }
    })
  : discoverFiles(MARKETPLACE)

if (!files.length) {
  console.log('  no marketplace files to review')
  process.exit(0)
}

let broken = 0
let flagged = 0

/** Pull each <Item> block out; regex is enough for a report and keeps this dependency-free. */
function items(xml) {
  return [...xml.matchAll(/<Item>([\s\S]*?)<\/Item>/g)].map(m => m[1])
}
function field(block, name) {
  const m = block.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`))
  return m ? m[1].trim() : ''
}
function cdata(block, name) {
  const m = block.match(new RegExp(`<${name}>\\s*(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?\\s*</${name}>`))
  return m ? m[1].trim() : ''
}

for (const file of files) {
  if (!existsSync(file.absPath)) {
    console.error(`\n  error  ${file.url} does not exist`)
    broken++
    continue
  }

  const meta = readXmlFile(file.absPath)
  console.log(`\n${'─'.repeat(72)}\n${file.url}`)

  if (!meta.ok) {
    console.error(`  error  ${meta.error}`)
    broken++
    continue
  }

  console.log(`  ${meta.name || "(no name)"}: ${meta.itemCount} items, by ${meta.author || '(no author)'}`)
  if (meta.description) console.log(`  ${meta.description}`)

  const xml = readFileSync(file.absPath, 'utf-8')
  const byType = {}
  const notes = []

  for (const block of items(xml)) {
    const type = field(block, 'Type') || 'Unknown'
    byType[type] = (byType[type] ?? 0) + 1
    const name = field(block, 'Name') || '(unnamed)'

    if (type === 'PowerShell') {
      const script = cdata(block, 'Script')
      const hits = SCRIPT_PATTERNS.filter(([re]) => re.test(script)).map(([, label]) => label)
      // Any PowerShell is worth reading; the hits say why it is urgent.
      notes.push({
        level: hits.length ? 'review' : 'note',
        text: `PowerShell "${name}"${hits.length ? ": " + hits.join(', ') : ''}`,
        detail: script.split('\n').slice(0, 6).map(l => '        ' + l.trim()).join('\n')
      })
    }

    if (type === 'FileFolder') {
      const path = field(block, 'Path')
      const action = field(block, 'Action')
      if (SENSITIVE_PATHS.some(re => re.test(path))) {
        notes.push({ level: 'review', text: `${action} on a system location: ${path} ("${name}")` })
      }
    }

    if (type === 'Registry') {
      const path = field(block, 'Path')
      const action = field(block, 'Action')
      const hit = SENSITIVE_KEYS.find(([re]) => re.test(path))
      if (action === 'DeleteKeyRecursively') {
        notes.push({ level: 'review', text: `recursive registry delete: ${path} ("${name}")` })
      } else if (hit) {
        notes.push({ level: 'note', text: `${hit[1]}: ${path} ("${name}")` })
      }
    }
  }

  console.log('  types: ' + Object.entries(byType).map(([t, n]) => `${t} ${n}`).join(', '))

  const toReview = notes.filter(n => n.level === 'review')
  const toNote = notes.filter(n => n.level === 'note')

  if (toReview.length) {
    flagged++
    console.log(`\n  NEEDS REVIEW (${toReview.length}):`)
    for (const n of toReview) {
      console.log(`    ! ${n.text}`)
      if (n.detail) console.log(n.detail)
    }
  }
  if (toNote.length) {
    console.log(`\n  worth a look (${toNote.length}):`)
    for (const n of toNote) console.log(`    - ${n.text}`)
  }
  if (!notes.length) console.log('  nothing flagged')
}

console.log(`\n${'─'.repeat(72)}`)
console.log(`  ${files.length} file(s) reviewed, ${flagged} with items needing a closer look`)
if (broken) {
  console.error(`  ${broken} file(s) could not be read\n`)
  process.exit(1)
}
console.log('  Flags are prompts for a human, not rejections. Read the items above before merging.\n')
