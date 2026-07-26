import { describe, it, expect, vi } from 'vitest'
import { isEscapeHandled, markEscapeHandled } from '../../src/core/escape'

/**
 * Regression cover for stacked-dialog Escape handling.
 *
 * Dialogs listen on `document`, so every open dialog sees the same keydown. Without
 * this claim mechanism, one Escape over a nested dialog closed both it and its parent.
 */
describe('escape claim', () => {
  it('reports an unclaimed event as unhandled', () => {
    expect(isEscapeHandled(new KeyboardEvent('keydown', { key: 'Escape' }))).toBe(false)
  })

  it('reports an event as handled once claimed', () => {
    const e = new KeyboardEvent('keydown', { key: 'Escape' })
    markEscapeHandled(e)
    expect(isEscapeHandled(e)).toBe(true)
  })

  it('tracks each event separately, so a later press is not pre-claimed', () => {
    const first = new KeyboardEvent('keydown', { key: 'Escape' })
    const second = new KeyboardEvent('keydown', { key: 'Escape' })
    markEscapeHandled(first)
    expect(isEscapeHandled(second)).toBe(false)
  })

  it('is idempotent', () => {
    const e = new KeyboardEvent('keydown', { key: 'Escape' })
    markEscapeHandled(e)
    markEscapeHandled(e)
    expect(isEscapeHandled(e)).toBe(true)
  })

  it('lets only the first of several listeners act on one event', () => {
    // Mirrors what BaseDialog and AboutDialog do when both are mounted.
    const e = new KeyboardEvent('keydown', { key: 'Escape' })
    const closed: string[] = []
    for (const name of ['inner', 'outer']) {
      if (isEscapeHandled(e)) continue
      markEscapeHandled(e)
      closed.push(name)
    }
    expect(closed).toEqual(['inner'])
  })
})

describe('open-dialog stack', () => {
  it('reports only the most recently opened dialog as top', async () => {
    const { pushDialog, popDialog, isTopDialog } = await import('../../src/core/escape')
    const outer = Symbol('outer')
    const inner = Symbol('inner')

    pushDialog(outer)
    expect(isTopDialog(outer)).toBe(true)

    pushDialog(inner)
    expect(isTopDialog(inner)).toBe(true)
    expect(isTopDialog(outer)).toBe(false)   // the parent must not act first

    popDialog(inner)
    expect(isTopDialog(outer)).toBe(true)
    popDialog(outer)
    expect(isTopDialog(outer)).toBe(false)
  })

  it('ignores a duplicate push and an unknown pop', async () => {
    const { pushDialog, popDialog, isTopDialog } = await import('../../src/core/escape')
    const a = Symbol('a')
    const b = Symbol('b')

    pushDialog(a); pushDialog(b); pushDialog(b)
    popDialog(b)
    expect(isTopDialog(a)).toBe(true)        // one pop is enough

    popDialog(Symbol('never-pushed'))
    expect(isTopDialog(a)).toBe(true)
    popDialog(a)
  })

  it('handles a dialog closing out of order', async () => {
    const { pushDialog, popDialog, isTopDialog } = await import('../../src/core/escape')
    const outer = Symbol('outer')
    const inner = Symbol('inner')

    pushDialog(outer); pushDialog(inner)
    popDialog(outer)                          // parent closes while child is open
    expect(isTopDialog(inner)).toBe(true)
    popDialog(inner)
  })
})

describe('escape claim survives a duplicated module instance', () => {
  it('two copies of the module agree, because the mark is on the event', async () => {
    // Regression: a module-level WeakSet gave each copy its own state, so stacked
    // dialogs silently stopped coordinating whenever the module graph was reloaded.
    const a = await import('../../src/core/escape')
    vi.resetModules()
    const b = await import('../../src/core/escape')

    const e = new KeyboardEvent('keydown', { key: 'Escape' })
    a.markEscapeHandled(e)
    expect(b.isEscapeHandled(e)).toBe(true)

    vi.resetModules()
  })
})
