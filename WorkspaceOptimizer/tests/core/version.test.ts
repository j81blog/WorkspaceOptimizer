import { describe, it, expect } from 'vitest'
import { formatVersion } from '../../src/core/version'

describe('formatVersion', () => {
  it('matches the existing Windows.xml stamp format', () => {
    expect(formatVersion(new Date(2026, 3, 29, 22, 30))).toBe('2026.429.2230')
  })

  it('does not pad single-digit months or the time', () => {
    expect(formatVersion(new Date(2026, 0, 5, 9, 7))).toBe('2026.105.907')
  })

  it('keeps two-digit months unambiguous by padding the day', () => {
    expect(formatVersion(new Date(2026, 9, 5, 0, 7))).toBe('2026.1005.7')
  })

  it('handles the end of the year', () => {
    expect(formatVersion(new Date(2026, 11, 31, 23, 59))).toBe('2026.1231.2359')
  })

  it('stamps midnight as a bare 0 rather than padding it', () => {
    expect(formatVersion(new Date(2026, 0, 1, 0, 0))).toBe('2026.101.0')
    expect(formatVersion(new Date(2026, 0, 1, 0, 1))).toBe('2026.101.1')
  })

  it('keeps every minute of a day distinct', () => {
    const seen = new Set<string>()
    for (let h = 0; h < 24; h++) {
      for (let m = 0; m < 60; m++) seen.add(formatVersion(new Date(2026, 0, 1, h, m)))
    }
    expect(seen.size).toBe(24 * 60)
  })

  it('never zero-pads a component', () => {
    for (let month = 0; month < 12; month++) {
      for (const day of [1, 15, 28, 31]) {
        for (const [h, m] of [[0, 0], [0, 1], [0, 7], [9, 7], [10, 0], [23, 59]]) {
          const d = new Date(2026, month, day, h, m)
          if (d.getMonth() !== month) continue   // skip the 31st of short months
          const parts = formatVersion(d).split('.')
          expect(parts).toHaveLength(3)
          for (const part of parts) {
            // A bare "0" is fine (a real midnight build); "0429" or "0000" is not.
            expect(part === '0' || !part.startsWith('0')).toBe(true)
          }
        }
      }
    }
  })

  it('sorts monotonically within a day', () => {
    const at = (h: number, m: number) => Number(formatVersion(new Date(2026, 9, 5, h, m)).split('.')[2])
    expect(at(0, 7)).toBeLessThan(at(9, 7))
    expect(at(9, 7)).toBeLessThan(at(22, 30))
  })
})
