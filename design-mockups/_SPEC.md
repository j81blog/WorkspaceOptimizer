# Workspace Optimizer — Mockup Build Spec (shared)

This is the authoritative control/option inventory and design-token reference for the
three redesign mockups. Each mockup is a SINGLE self-contained static `.html` file
(inline `<style>`, no JS framework, minimal vanilla JS only for theme toggle / tab
switching / drawer open). It must visually demonstrate the new layout AND expose
**every** button and option listed below — nothing may be dropped.

## What the app is
"Workspace Optimizer" — a web tool that edits an XML template describing Windows
optimization items (registry tweaks, services, scheduled tasks, store apps, PowerShell
scripts, file/folder ops) and which operating systems each applies to. Output is an XML
template + a PowerShell deployment script.

## MANDATORY controls/options (must all be visible in the mockup)

### Top navbar / global actions
- Brand: logo image placeholder + title "Workspace Optimizer"
- "New from Default"  (tooltip: Create a new template from built-in defaults)
- "Open Template"     (tooltip: Open an existing XML template file)
- "Download XML"      (primary/accent style; disabled state exists)
- "Download Script"   (primary/accent style — downloads PowerShell deployment script)
- "Manage OS"         (opens OS manager dialog)
- "PDF Report"        (generates PDF summary; disabled state exists)
- "About"
- Theme toggle (☀ Light / ☾ Dark)
- Sidebar/explorer toggle (hamburger ☰)
- Filename indicator + "● Modified" dirty indicator

### Sidebar — search & filter
- Search text input ("Search items…") with a clear (×) button
- Category filter <select> (All + categories)
- Type filter <select> (All, Registry, Service, ScheduledTask, StoreApp, PowerShell, FileFolder)
- OS filter <select> (All + OS names)

### Sidebar — item actions
- "+ New" (add item; green/add style)
- "Duplicate" (purple/dup style; disabled when nothing selected)
- "Delete" (red/del style; disabled when nothing selected)
- View toggle: "Category" vs "Deploy Order"
- Sort direction toggle (A→Z / Z→A), only in Category view

### Sidebar — item list
- Grouped by category with collapsible headers showing a count badge
- Each item row: type icon, name, order badge (number), optional error "!" badge,
  description (truncated), and in Deploy-Order view the category meta line
- Footer: item count + error count

### Item editor — General card
- Name * (text)
- Order (number 0–99999)
- Description (multi-line / autogrow textarea)
- Type * <select> (the six types)
- Category * <select> + "+" add-category button (opens small Add Category dialog: input, Cancel, Add)

### Item editor — Payload card (changes by type — show Registry as the example, mention others)
- Registry: Hive <select> (HKLM/HKCU/...), Path, Name, Action <select> (SetValue/RemoveValue/...),
  Value, Registry Type <select> (DWord/String/...)
- Service: Name, Action <select> (Disabled/...)
- ScheduledTask: Name, Path, Action <select>
- StoreApp: Name
- PowerShell: Engine <select> (powershell/pwsh), Script (code area)
- FileFolder: Path, Action <select> (Remove/...), Item Type <select> (File/Folder), New Name

### Item editor — OS Mapping panel (right column)
- Two sub-sections: "Client OS" and "Server OS"
- Column headers: OS | Execute | Physical | Virtual
- Each OS row: enable checkbox + name, then Execute / Physical / Virtual checkboxes
  (Execute disabled until row enabled; Physical/Virtual gate Execute)

### Item editor — breadcrumb + validation
- Breadcrumb bar: category › item name + type badge
- Per-item validation issues list (error ✕ / warning ⚠ rows)
- Bottom validation bar: status (✓ Valid / N errors, N warnings), expandable issue list

### Manage OS dialog
- Left: OS list (name + tag), "Add OS", "Delete OS" (disabled when none selected)
- Right detail: Tag *, Name *, Abbreviation (auto-derived placeholder), "Server OS" checkbox
- Build section: "BuildStartsWith" list, "Add" / "Remove" build buttons
- Footer: Cancel / Save

### PDF dialog & About dialog
- Represent at least a placeholder for "PDF Report" options and an "About" panel
  (version info, links). A compact representation is fine.

## Design tokens (use these so mockups feel native; support BOTH themes via [data-theme])

Font: 'Montserrat', sans-serif (link Google Fonts). Border radius ~6–10px. Compact (11–13px text).

DARK theme:
  nav-bg #1e293b; nav-text #f1f5f9; accent (cyan) #38bdf8 / #7dd3fc;
  app/sidebar bg #0f172a; card/panel bg #1a2540; field bg #131f35; borders #1e293b/#2d3f57;
  text #e2e8f0; muted #475569/#64748b; add #6fcf97 (bg #1d4e3a); del #ff8a8a (bg #4a1a1a);
  dup #b39ddb (bg #2a2050); valid #2dd4bf; warning #fbbf24; error #f87171.
  Type accents: Registry #fb923c, Service #38bdf8, ScheduledTask #a78bfa, StoreApp #f472b6,
  PowerShell #4ade80, FileFolder #2dd4bf.

LIGHT theme:
  nav stays dark #1e293b; app/sidebar bg #f8fafc; card bg #ffffff; field bg #fafbfc;
  borders #e2e8f0/#cbd5e1; text #1e293b; muted #64748b/#94a3b8; accent (blue) #3b82f6/#2563eb;
  add #2563eb-ish, del #dc2626, dup #7c3aed; valid #2563eb; same type accents.

## Output rules
- One file, fully self-contained, opens directly in a browser.
- Populate with 6–10 realistic sample items (e.g. "Disable Telemetry", "Remove Xbox Game Bar",
  "Disable SysMain Service") across multiple categories so the layout reads as real.
- Default to DARK theme, with a working theme toggle.
- Make it look polished and production-grade, NOT a wireframe. Real spacing, hover states,
  the type-accent colors, proper disabled styling.
- Add a small fixed "Design N — <name>" badge in a corner so reviewers can tell them apart.
