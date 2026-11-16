/// <reference types="node" />
import { describe, it, expect } from 'vitest'
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
// @ts-expect-error plain .mjs without types
import { readXmlFile, buildEntry, pruneEntry } from '../../scripts/catalog-lib.mjs'

describe('catalog-lib sha256', () => {
  it('writes the same sha256 into the entry for LF, CRLF and BOM files', () => {
    const dir = mkdtempSync(join(tmpdir(), 'wo-lib-'))
    try {
      const xml = '<Items>\n<Metadata><Name>N</Name></Metadata>\n<Item></Item>\n</Items>\n'
      const hashes = [xml, xml.replace(/\n/g, '\r\n'), '﻿' + xml].map((text, i) => {
        const abs = join(dir, `f${i}.xml`)
        writeFileSync(abs, text, 'utf-8')
        const parsed = readXmlFile(abs)
        return pruneEntry(buildEntry({ kind: 'template', url: `template/f${i}.xml` }, parsed, undefined)).sha256
      })
      expect(hashes[0]).toMatch(/^[0-9a-f]{64}$/)
      expect(new Set(hashes).size).toBe(1)
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})
