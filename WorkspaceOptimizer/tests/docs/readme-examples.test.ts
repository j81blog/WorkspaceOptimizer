/**
 * The README documents rules the app enforces, so its examples are checked against the
 * real parser and validator. A doc example that no longer satisfies its own rules is a
 * bug in the docs. This is how the required-metadata change was caught.
 */
import { it, expect } from 'vitest'
import readme from '../../../README.md?raw'
import { parseXml } from '../../src/core/parser'
import { validate } from '../../src/core/validator'

it('the README XML example still parses and validates', () => {
  const blocks = [...readme.replace(/\r\n/g,'\n').matchAll(/```xml\n([\s\S]*?)```/g)].map(m => m[1])
  const full = blocks.find(b => b.includes('<Items>'))
  expect(full, 'no <Items> example found').toBeTruthy()

  const doc = parseXml(full!)
  expect(doc.items.length).toBeGreaterThan(0)
  // The example must satisfy the rules the README itself documents.
  expect(validate(doc).errors).toEqual([])
})

it('the Metadata example in the docs parses', () => {
  const blocks = [...readme.replace(/\r\n/g,'\n').matchAll(/```xml\n([\s\S]*?)```/g)].map(m => m[1])
  const meta = blocks.find(b => b.trim().startsWith('<Metadata>'))
  expect(meta, 'no <Metadata> example found').toBeTruthy()
  const doc = parseXml(`<Items>${meta}<SupportedOS></SupportedOS></Items>`)
  expect(doc.metadata).toMatchObject({ name: expect.any(String), author: expect.any(String) })
  expect(doc.metadata!.tags.length).toBeGreaterThan(0)
})

it('the index.json example is valid JSON with required fields', () => {
  const blocks = [...readme.replace(/\r\n/g,'\n').matchAll(/```jsonc?\n([\s\S]*?)```/g)].map(m => m[1])
  const cat = blocks.find(b => b.includes('"entries"'))
  expect(cat, 'no catalog example found').toBeTruthy()
  const json = JSON.parse(cat!.replace(/\/\/.*$/gm, ''))
  for (const e of json.entries) {
    for (const f of ['id','kind','name','url']) expect(e[f], `entry missing ${f}`).toBeTruthy()
    expect(['template','snippet']).toContain(e.kind)
  }
})
