# Changelog

All notable changes to this project are documented here.

## 12.08.2026

### Validation and tooling

CHANGE: Dropped the unused PrimeIcons dependency, removing about 646 kB of font files from the build
CHANGE: PrimeVue stays on 4.x, which is MIT licensed, so the project and its forks remain GPL-3 with no license key required

## 11.08.2026

### Interface

FIX: Execute in the OS table is now disabled until Physical or Virtual is set, instead of accepting the tick and silently discarding it

### Optimization script

FIX: The downloaded Invoke-WindowsOptimization.ps1 kept the line endings it was signed with, so its signature verifies again instead of reporting NotSigned

### Validation and tooling

NEW: The signed script is checked on every pull request for its signature, line endings, encoding and comment-based help
FIX: The marketplace catalog is generated identically on Windows and Linux, so a template description no longer changes index.json depending on who ran the sync

## 26.07.2026

### Marketplace

NEW: Marketplace for browsing and loading shared templates and snippets, with an empty starter catalog
NEW: Snippet merge with per-item review and duplicate/conflict detection
NEW: Category and deploy order can be changed per item or in bulk before a snippet is imported
NEW: Several marketplace catalogs can be configured at once and are merged into one list
NEW: Configured catalogs add to the bundled one; VITE_MARKETPLACE_DISABLE_BUNDLED uses only your own
NEW: Trusted hosts can be whitelisted to import without a confirmation prompt
NEW: Marketplace and .reg import can each be disabled per deployment
NEW: Warning on download when a template contains imported items
NEW: VITE_BRAND_REPO_URL links an empty Marketplace to the source repository
CHANGE: A template loaded from the Marketplace is named after its entry, not its id
CHANGE: A snippet referencing an undefined OS now offers to add it, disabled until its build numbers are set
FIX: Line breaks in a Marketplace description are now shown instead of being collapsed into one paragraph
FIX: Marketplace entries in a same-origin catalog resolved to the wrong path and failed to load
FIX: A wrong catalog URL now says the path was not found instead of reporting a parse error

### Importing .reg files

NEW: Import wizard for .reg files, with bulk defaults and a per-row review step

### Template properties and metadata

NEW: Templates and snippets describe themselves in Metadata, so catalogs can be generated with npm run catalog:sync
NEW: Template Properties dialog for the name, description, author, category and tags, with an auto-generated Id
CHANGE: Downloading XML now requires a template Name, Description and Author
CHANGE: Template version is auto-stamped on download when the document has unsaved changes
CHANGE: An item with no Category now inherits the file's Metadata Category before falling back to "Imported"
FIX: Metadata block is no longer dropped when downloading a template

### Interface

NEW: Options menu grouping every template action, with Add from… as a submenu
NEW: New template starts an empty document, so you can build one from scratch
NEW: What's New dialog in About, showing the newest release expanded and earlier ones collapsed
CHANGE: Manage OS and PDF report moved from the toolbar into the Options menu
CHANGE: Every dialog now shares one title bar, footer and Escape behavior
FIX: Clicking a missing-Name, Description or Author error now opens Properties instead of doing nothing
FIX: A new item can no longer be added when no template is open, start one with Options → New template
FIX: Escape now closes only the innermost dialog when dialogs are stacked
FIX: Manage OS now closes on Escape, like every other dialog
FIX: Dialogs mounted in the open state now initialize instead of rendering empty

### Validation and tooling

NEW: The build validates every marketplace XML file and reports stale or unreferenced entries
NEW: Build fails when the bundled catalog or marketplace variables are invalid
NEW: CI runs the test suite and fails when the catalog is out of sync
NEW: Pull requests are validated by CI, with templates and a contributing guide for marketplace submissions
NEW: npm run review:submission reports what a submitted template or snippet would do to a machine
FIX: Empty values are now allowed for String, ExpandString and MultiString registry types
FIX: Default template failed to load when deployed to a subpath
FIX: Corrected the XML format example and first-load description in the README
