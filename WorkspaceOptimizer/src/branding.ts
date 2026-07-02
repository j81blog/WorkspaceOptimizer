/**
 * Branding / white-labeling.
 *
 * A fork can rebrand the app WITHOUT changing any code, by setting GitHub Actions
 * repository Variables (Settings → Secrets and variables → Actions → Variables).
 * Those are passed into the Vite build as `VITE_BRAND_*` env vars (see deploy.yml)
 * and Vite exposes any `VITE_`-prefixed var on `import.meta.env`.
 *
 * Logo resolution order:
 *   1. VITE_BRAND_LOGO_VALUE  (an http(s) URL, a full data: URI, OR raw base64 —
 *                              raw base64 is wrapped into a data: URI with the
 *                              image type sniffed from its magic bytes)
 *   2. public/brand-logo.png  (convention file dropped in by the fork)
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
 * Sniff an image MIME type from the magic bytes at the start of a base64 string.
 * Decodes only the first few bytes (enough to identify the format). Falls back
 * to image/png when the signature is unrecognized.
 */
export function sniffImageMime(base64: string): string {
  let head: string
  try {
    // The header sits in the first handful of bytes; ~16 base64 chars is plenty.
    head = atob(base64.slice(0, 24))
  } catch {
    return 'image/png'
  }
  const b = (i: number) => head.charCodeAt(i) & 0xff
  if (b(0) === 0x89 && b(1) === 0x50 && b(2) === 0x4e && b(3) === 0x47) return 'image/png'   // ‰PNG
  if (b(0) === 0xff && b(1) === 0xd8 && b(2) === 0xff) return 'image/jpeg'                    // JPEG
  if (b(0) === 0x47 && b(1) === 0x49 && b(2) === 0x46) return 'image/gif'                     // GIF8
  if (b(0) === 0x52 && b(1) === 0x49 && b(2) === 0x46 && b(3) === 0x46 &&
      b(8) === 0x57 && b(9) === 0x45 && b(10) === 0x42 && b(11) === 0x50) return 'image/webp' // RIFF…WEBP
  // SVG is text; a base64-encoded SVG starts with "<?xml" or "<svg".
  if (head.startsWith('<?xml') || head.startsWith('<svg') || head.includes('<svg')) return 'image/svg+xml'
  return 'image/png'
}

/**
 * Resolve the configured logo value into something usable as an <img src>.
 * Accepts:
 *   - an http(s) URL                       → used as-is
 *   - a full data: URI                     → used as-is
 *   - a root/relative path or filename     → used as-is
 *   - raw base64                           → wrapped into
 *     `data:<sniffed-mime>;base64,<value>`
 *
 * Detection is base64-first: a value made up solely of base64 characters (after
 * whitespace removal) and long enough to be image data is treated as base64.
 * Everything else — including paths like `/logo.png`, which can otherwise look
 * base64-ish because `/` is a valid base64 character — is passed through as a URL.
 */
export function resolveLogoValue(raw: string | undefined): string | undefined {
  const v = str(raw)
  if (!v) return undefined
  if (/^(https?:|data:)/i.test(v)) return v
  // Raw base64: only [A-Za-z0-9+/] with optional '=' padding, no '.', ':' or whitespace
  // inside, and long enough to plausibly be an image. Paths and filenames (which
  // contain '.', or are short) fall through to passthrough.
  const cleaned = v.replace(/\s+/g, '')
  if (cleaned.length >= 32 && /^[A-Za-z0-9+/]+={0,2}$/.test(cleaned)) {
    return `data:${sniffImageMime(cleaned)};base64,${cleaned}`
  }
  return v
}

const logoValue = resolveLogoValue(env.VITE_BRAND_LOGO_VALUE)

/**
 * Whether a fork has customized branding at all. Used to decide if the
 * "Powered by Workspace Optimizer" attribution footer should appear.
 */
export const isRebranded = Boolean(
  str(env.VITE_BRAND_NAME) ||
  str(env.VITE_BRAND_VENDOR) ||
  logoValue
)

export const brand = {
  /** App / product name shown in the navbar, browser tab, and About title. */
  name: str(env.VITE_BRAND_NAME) ?? 'Workspace Optimizer',

  /** Logo: explicit value (URL / data: URI / raw base64) wins; otherwise the
   *  convention file (which falls back to the bundled default via onLogoError
   *  below if the file is absent). */
  logo: logoValue ?? conventionLogoUrl,

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

/**
 * Point the browser-tab favicon at the brand logo, so white-label forks get
 * their own favicon without touching index.html. If the brand logo fails to
 * load (e.g. a missing convention file), fall back to the bundled default —
 * mirroring `onLogoError` for the on-page `<img>`.
 */
export function applyFavicon() {
  let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]')
  if (!link) {
    link = document.createElement('link')
    link.rel = 'icon'
    document.head.appendChild(link)
  }
  const icon = link
  const test = new Image()
  test.onload = () => { icon.href = brand.logo }
  test.onerror = () => { icon.href = brand.fallbackLogo }
  test.src = brand.logo
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
  applyFavicon()

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
