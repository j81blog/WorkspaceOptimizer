/**
 * Branding / white-labeling.
 *
 * A fork can rebrand the app WITHOUT changing any code, by setting GitHub Actions
 * repository Variables (Settings → Secrets and variables → Actions → Variables).
 * Those are passed into the Vite build as `VITE_BRAND_*` env vars (see deploy.yml)
 * and Vite exposes any `VITE_`-prefixed var on `import.meta.env`.
 *
 * Logo resolution order:
 *   1. VITE_BRAND_LOGO_URL   (an externally hosted image URL)
 *   2. public/brand-logo.png (convention file dropped in by the fork)
 *   3. bundled default        (src/assets/WorkspaceOptimizer.png)
 *
 * The original author credit is intentionally NOT configurable: it is always shown
 * in the About dialog. A fork's own vendor line is layered alongside it, never
 * replacing it.
 */
import defaultLogoUrl from './assets/WorkspaceOptimizer.png'

const env = import.meta.env

/** Permanent, non-overridable original author credit (always shown in About). */
export const ORIGINAL_CREDIT = 'John Billekens Consultancy & AppVentiX'

function str(v: unknown): string | undefined {
  const s = typeof v === 'string' ? v.trim() : ''
  return s.length ? s : undefined
}

/** Where the convention logo file would live, respecting the deploy base path. */
const conventionLogoUrl = `${env.BASE_URL}brand-logo.png`

/**
 * Whether a fork has customized branding at all. Used to decide if the
 * "Powered by Workspace Optimizer" attribution footer should appear.
 */
export const isRebranded = Boolean(
  str(env.VITE_BRAND_NAME) ||
  str(env.VITE_BRAND_VENDOR) ||
  str(env.VITE_BRAND_LOGO_URL)
)

export const brand = {
  /** App / product name shown in the navbar, browser tab, and About title. */
  name: str(env.VITE_BRAND_NAME) ?? 'Workspace Optimizer',

  /** Logo: explicit URL wins; otherwise the convention file (which falls back
   *  to the bundled default via onLogoError below if the file is absent). */
  logo: str(env.VITE_BRAND_LOGO_URL) ?? conventionLogoUrl,

  /** The bundled logo, used as the final fallback when the convention file 404s. */
  fallbackLogo: defaultLogoUrl,

  /** Fork's "Created by …" vendor line (shown in addition to ORIGINAL_CREDIT). */
  vendor: str(env.VITE_BRAND_VENDOR),

  /** Fork's website link shown in About (label derived from the URL host). */
  url: str(env.VITE_BRAND_URL),

  /** Fork's About description; falls back to the original product description. */
  description: str(env.VITE_BRAND_DESCRIPTION) ??
    'A tool for building and editing Windows cleanup & optimization templates.',

  /** Accent color (a single hex like #38bdf8). Empty = keep the built-in accent. */
  accent: str(env.VITE_BRAND_ACCENT),
}

/** `<img @error>` handler: if the convention logo file is missing, use the bundled one. */
export function onLogoError(e: Event) {
  const img = e.target as HTMLImageElement
  if (img.src !== brand.fallbackLogo) img.src = brand.fallbackLogo
}

/** Human-readable label for the fork website link (host without protocol/www). */
export function brandUrlLabel(): string {
  if (!brand.url) return ''
  try {
    return new URL(brand.url).host.replace(/^www\./, '')
  } catch {
    return brand.url
  }
}

/**
 * Apply brand-driven runtime side effects: document title and accent color
 * override. Call once at startup. Accent is applied by overriding the small set
 * of accent CSS custom properties used across both themes.
 */
export function applyBranding() {
  document.title = brand.name

  if (brand.accent) {
    const root = document.documentElement.style
    // These are the accent tokens defined in style.css for both themes.
    root.setProperty('--item-bar', brand.accent)
    root.setProperty('--os-accent', brand.accent)
    root.setProperty('--sb-cat-txt', brand.accent)
    root.setProperty('--bc-badge-txt', brand.accent)
    root.setProperty('--field-focus-bdr', brand.accent)
    root.setProperty('--splitter-hover', brand.accent)
  }
}
