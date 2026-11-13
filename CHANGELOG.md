# Changelog

All notable changes to this project are documented here.

## 13.11.2026

### Default template

FIX: Windows 11 22H2 and 23H2 are recognized again; the OS now matches the exact builds 22000, 22621, 22631, 26100, 26200, 26300 and 28000
FIX: Disable default system screensaver writes ScreenSaveActive as a String, its actual registry type
CHANGE: Windows Update, Delete Temporary Installation Files and Clear All Event Logs no longer run on physical machines
CHANGE: The Windows Update description now says what the item does: it turns off automatic updates
CHANGE: The two Edge Update default policies explain that they also block WebView2 installs and updates
NEW: Remove hibernation file turns hibernation off with powercfg, so hiberfil.sys is deleted as well

### Optimization script

NEW: Exit codes for task sequences: 0 success, 1 fatal, 2 one or more items failed, 3 no matching OS
NEW: -WhatIf lists what would be applied without changing anything
NEW: Store apps are also removed from the provisioned image, so they no longer return for new profiles
NEW: Registry changes log the previous value, and an empty value name sets or deletes the key's (Default) value
NEW: Nutanix AHV, Bochs and VirtualBox are recognized as virtual, also from the BIOS version and serial number
CHANGE: The log is written to %ProgramData%\WorkspaceOptimizer\Logs, so the temp cleanup can no longer delete it mid-run
CHANGE: The script requires an elevated, 64-bit PowerShell session and says so up front
FIX: When the platform cannot be detected the script stops, instead of treating a virtual machine as physical
FIX: A PowerShell item whose command fails with an exit code is reported as Failed instead of Success
FIX: An error from a single-line script output is shown in full, not as its first character
FIX: A script written without CDATA runs, and an empty script is reported as Failed instead of Skipped
FIX: Unloading the Default User hive is retried, and the Default profile location is read from the registry
FIX: File and folder actions refuse empty, relative and drive-root paths, and treat paths literally

### Interface

NEW: Unsaved work is kept as a draft in the browser and offered for restore on the next visit
NEW: Options → Download draft… saves a template that still has validation errors
NEW: Opening a file lists comments and unknown elements that saving would drop
FIX: Items with a type this version does not know are kept and saved unchanged, instead of losing their payload
FIX: Re-opening the same file after cancelling the discard prompt works
CHANGE: Fonts are bundled with the app instead of loaded from Google Fonts, and a Content Security Policy is set

### Validation and tooling

NEW: OS tags must be valid XML names, so a tag with a space can no longer produce an unreadable file
NEW: Hive, DWord and Qword ranges, PowerShell engine and characters invalid in XML are validated
FIX: Registry string values keep leading and trailing spaces
FIX: A hive written in any case, such as hklm, is read as HKLM instead of being rejected
FIX: A PowerShell script containing ]]> survives a save and reload
FIX: .reg import: an empty (Default) value no longer blocks the download, and a comment ending in a backslash no longer swallows the next line

### Marketplace

NEW: Catalog entries carry a sha256; a file that no longer matches it is refused
CHANGE: Content is only imported without confirmation when it has a sha256 and is still on a trusted host after redirects

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
