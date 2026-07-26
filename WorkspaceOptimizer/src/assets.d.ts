declare module '*.png' { const src: string; export default src }
declare module '*.ico' { const src: string; export default src }
declare module '*?raw' { const content: string; export default content }

declare const __BUILD_DATE__: string
declare const __SCRIPT_VERSION__: string
declare const __XML_VERSION__: string

interface ImportMetaEnv {
  readonly BASE_URL: string
  readonly VITE_BRAND_NAME?: string
  readonly VITE_BRAND_VENDOR?: string
  readonly VITE_BRAND_URL?: string
  readonly VITE_BRAND_DESCRIPTION?: string
  readonly VITE_BRAND_LOGO_VALUE?: string
  readonly VITE_BRAND_ACCENT?: string
  readonly VITE_BRAND_REPO_URL?: string
  readonly VITE_MARKETPLACE_URL?: string
  readonly VITE_MARKETPLACE_TRUSTED_HOSTS?: string
  readonly VITE_MARKETPLACE_DISABLE_BUNDLED?: string
  readonly VITE_DISABLE_MARKETPLACE?: string
  readonly VITE_DISABLE_REG_IMPORT?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
