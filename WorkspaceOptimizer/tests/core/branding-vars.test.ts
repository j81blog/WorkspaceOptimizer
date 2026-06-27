import { describe, it, expect, afterEach, vi } from 'vitest'

/**
 * `brand` and `isRebranded` are computed once at module load from import.meta.env,
 * so each env scenario requires a fresh import. This helper stubs the given env
 * vars, resets the module registry, and re-imports branding.ts.
 */
async function loadBranding(env: Record<string, string | undefined>) {
  vi.resetModules()
  for (const [k, v] of Object.entries(env)) {
    if (v === undefined) vi.stubEnv(k, '')
    else vi.stubEnv(k, v)
  }
  return await import('../../src/branding')
}

afterEach(() => {
  vi.unstubAllEnvs()
  vi.resetModules()
})

describe('brand defaults (no variables set)', () => {
  it('falls back to built-in name and description; optional fields empty', async () => {
    const { brand, isRebranded } = await loadBranding({
      VITE_BRAND_NAME: '', VITE_BRAND_VENDOR: '', VITE_BRAND_URL: '',
      VITE_BRAND_DESCRIPTION: '', VITE_BRAND_ACCENT: '', VITE_BRAND_LOGO_VALUE: '',
    })
    expect(brand.name).toBe('Workspace Optimizer')
    expect(brand.description).toContain('Windows')
    expect(brand.vendor).toBeUndefined()
    expect(brand.url).toBeUndefined()
    expect(brand.accent).toBeUndefined()
    expect(isRebranded).toBe(false)
  })

  it('treats whitespace-only values as unset', async () => {
    const { brand, isRebranded } = await loadBranding({
      VITE_BRAND_NAME: '   ', VITE_BRAND_VENDOR: '  ', VITE_BRAND_ACCENT: ' ',
    })
    expect(brand.name).toBe('Workspace Optimizer')
    expect(brand.vendor).toBeUndefined()
    expect(brand.accent).toBeUndefined()
    expect(isRebranded).toBe(false)
  })
})

describe('brand overrides', () => {
  it('applies name, vendor, url, description, accent', async () => {
    const { brand } = await loadBranding({
      VITE_BRAND_NAME: 'Contoso Optimizer',
      VITE_BRAND_VENDOR: 'Contoso IT',
      VITE_BRAND_URL: 'https://contoso.example',
      VITE_BRAND_DESCRIPTION: 'Internal Windows tuning tool',
      VITE_BRAND_ACCENT: '#e11d48',
    })
    expect(brand.name).toBe('Contoso Optimizer')
    expect(brand.vendor).toBe('Contoso IT')
    expect(brand.url).toBe('https://contoso.example')
    expect(brand.description).toBe('Internal Windows tuning tool')
    expect(brand.accent).toBe('#e11d48')
  })

  it('trims surrounding whitespace on values', async () => {
    const { brand } = await loadBranding({ VITE_BRAND_NAME: '  Contoso  ' })
    expect(brand.name).toBe('Contoso')
  })
})

describe('isRebranded', () => {
  it('is true when only the name is set', async () => {
    const { isRebranded } = await loadBranding({ VITE_BRAND_NAME: 'X' })
    expect(isRebranded).toBe(true)
  })
  it('is true when only the vendor is set', async () => {
    const { isRebranded } = await loadBranding({ VITE_BRAND_VENDOR: 'Y' })
    expect(isRebranded).toBe(true)
  })
  it('is true when only the logo is set', async () => {
    const { isRebranded } = await loadBranding({
      VITE_BRAND_LOGO_VALUE: 'https://x/y.png',
    })
    expect(isRebranded).toBe(true)
  })
  it('is NOT triggered by url / description / accent alone', async () => {
    // Only name, vendor, and logo flip the attribution footer.
    const { isRebranded } = await loadBranding({
      VITE_BRAND_URL: 'https://x', VITE_BRAND_DESCRIPTION: 'desc', VITE_BRAND_ACCENT: '#fff',
    })
    expect(isRebranded).toBe(false)
  })
})

describe('brandUrlLabel', () => {
  it('returns empty string when no url is set', async () => {
    const { brandUrlLabel } = await loadBranding({ VITE_BRAND_URL: '' })
    expect(brandUrlLabel()).toBe('')
  })
  it('strips protocol and www, keeping the host', async () => {
    const { brandUrlLabel } = await loadBranding({ VITE_BRAND_URL: 'https://www.contoso.example/path' })
    expect(brandUrlLabel()).toBe('contoso.example')
  })
  it('keeps a non-www host as-is', async () => {
    const { brandUrlLabel } = await loadBranding({ VITE_BRAND_URL: 'https://it.contoso.example' })
    expect(brandUrlLabel()).toBe('it.contoso.example')
  })
  it('falls back to the raw value for an unparseable url', async () => {
    const { brandUrlLabel } = await loadBranding({ VITE_BRAND_URL: 'not a url' })
    expect(brandUrlLabel()).toBe('not a url')
  })
})

describe('applyBranding', () => {
  it('sets document.title to the brand name', async () => {
    const { applyBranding } = await loadBranding({ VITE_BRAND_NAME: 'Contoso Optimizer' })
    applyBranding()
    expect(document.title).toBe('Contoso Optimizer')
  })

  it('overrides accent CSS custom properties when accent is set', async () => {
    const { applyBranding } = await loadBranding({ VITE_BRAND_ACCENT: '#e11d48' })
    applyBranding()
    const root = document.documentElement.style
    expect(root.getPropertyValue('--item-bar')).toBe('#e11d48')
    expect(root.getPropertyValue('--os-accent')).toBe('#e11d48')
    expect(root.getPropertyValue('--field-focus-bdr')).toBe('#e11d48')
  })

  it('does not touch accent properties when accent is unset', async () => {
    document.documentElement.style.removeProperty('--item-bar')
    const { applyBranding } = await loadBranding({ VITE_BRAND_ACCENT: '', VITE_BRAND_NAME: 'Z' })
    applyBranding()
    expect(document.documentElement.style.getPropertyValue('--item-bar')).toBe('')
  })
})
