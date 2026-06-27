# Workspace Optimizer

Browser-based editor for Windows optimization template. Load, edit, validate, and export XML templates that drive registry, service, scheduled task, app removal, PowerShell, and file/folder actions across multiple Windows OS versions. No install, no backend — runs entirely in your browser.

**Live app:** https://workspaceoptimizer.j81.nl/

---

## What is a template?

A template is an XML file that describes a set of configuration actions to apply to a Windows machine. Each item in the template defines:

- **What** to do (type + payload)
- **Where** it applies (which OS versions, physical/virtual/execute flags)
- **How** it is organized (category, order, description)

The editor lets you create and maintain these templates visually, without touching XML directly.

---

## Getting started

Open the app at the link above. On first load it automatically opens the built-in `Windows.xml` default template so you can explore a real example right away.

To start from scratch, click **New from Default** in the toolbar — this resets to the default template.
To open your own file, click **Open Template** and select a `.xml` template from your computer.

---

## Interface overview

The app uses a **Command Center** layout: a horizontal **toolbar** across the top
holds the brand and every global action, below it on the left is the **item list
(explorer)**, and the rest of the window is the focused **item editor**.

```
┌─────────────────────────────────────────────────────────────┐
│ Toolbar: logo · brand │ actions… │ filename · ● Modified · ☾ │
├──────────────┬──────────────────────────────────────────────┤
│              │                                               │
│  Item list   │  Item editor                                  │
│  (explorer)  │  (General + Payload | OS Mapping)             │
│              │                                               │
│              ├──────────────────────────────────────────────┤
│              │  Validation bar                               │
│              │                                               │
└──────────────┴──────────────────────────────────────────────┘
```

> This Command Center layout is the **default look with no configuration**. A fork can
> restyle the brand (name, logo, accent color) on top of it via repository Variables —
> see [White-labeling for forks](#white-labeling-for-forks). Branding overrides the
> appearance; the layout stays the same.

### Toolbar actions

The horizontal toolbar holds the brand on the left and every global action as a
labeled button; the current filename, a **Modified** indicator, and the theme toggle
sit on the right.

| Button               | Action                                                                               |
| -------------------- | ------------------------------------------------------------------------------------ |
| **New from Default** | Reset to the built-in default template                                               |
| **Open Template**    | Load a `.xml` template file from disk, edit your own template                        |
| **Download XML**     | Save the current template as an XML file (disabled when there are validation errors) |
| **Download Script**  | Save the latest PowerShell script, to apply the optimization                         |
| **Manage OS**        | Add, edit, or remove OS definitions                                                  |
| **PDF Report**       | Export a formatted PDF overview of all items                                         |
| **About**            | Open the About dialog (versions, credits)                                            |
| **☾ / ☀**           | Toggle dark/light theme (remembers your preference)                                  |

The right side of the toolbar shows the current filename and a yellow **Modified**
indicator when there are unsaved changes.

### Sidebar

Lists all items in the template. You can:

- **Search** by name, description, or category using the search box
- **Filter** by category, type, or OS using the dropdowns
- **Sort** by category grouping or numeric order
- **Add a new item** with the `+` button at the top
- **Select an item** to open it in the editor

Each item row shows its type icon, name, category, and which OS versions it is mapped to.

### Item editor

Editing area for the selected item, split into two columns:

- **Left column** — General fields (name, description, type, category, order) and the type-specific payload
- **Right column** — OS Mapping table

Changes are applied immediately; the Modified indicator appears in the toolbar.

---

## Item types and their fields

### Registry

Reads or writes a Windows registry value.

| Field         | Description                                                         |
| ------------- | ------------------------------------------------------------------- |
| Hive          | `HKLM`, `HKCU`, `HKU`, or `HKU\DefaultUser`                         |
| Path          | Registry key path (without the hive)                                |
| Name          | Value name; leave empty for the default value                       |
| Action        | `SetValue`, `DeleteKey`, `DeleteKeyRecursively`, `DeleteValue`      |
| Value         | Data to write (for SetValue)                                        |
| Registry Type | `String`, `ExpandString`, `Binary`, `DWord`, `MultiString`, `Qword` |

### Service

Controls a Windows service.

| Field  | Description                       |
| ------ | --------------------------------- |
| Name   | Service name                      |
| Action | `Disabled`, `Automatic`, `Manual` |

### Scheduled Task

Enables or disables a scheduled task.

| Field  | Description                                      |
| ------ | ------------------------------------------------ |
| Name   | Task name                                        |
| Path   | Task folder path (e.g. `\Microsoft\Windows\...`) |
| Action | `Enabled`, `Disabled`                            |

### Store App

Removes a Windows Store / AppX package.

| Field | Description                         |
| ----- | ----------------------------------- |
| Name  | Package family name or display name |

### PowerShell

Runs a PowerShell script.

| Field  | Description                                                 |
| ------ | ----------------------------------------------------------- |
| Engine | `powershell` (Windows PowerShell) or `pwsh` (PowerShell 7+) |
| Script | The script content                                          |

### FileFolder

Performs a file or folder operation.

| Field     | Description                      |
| --------- | -------------------------------- |
| Path      | Full path to the file or folder  |
| Action    | `Remove`, `Rename`               |
| Item Type | `File` or `Folder`               |
| New Name  | Required when Action is `Rename` |

---

## OS Mapping

Each item has an OS mapping that controls on which operating systems the action runs and in what context.

The OS Mapping card lists every OS the template supports, grouped into **Client OS**
and **Server OS**. Each OS row has a leading checkbox (next to the OS name) plus three
behavior checkboxes:

| Column        | Meaning                                                              |
| ------------- | ------------------------------------------------------------------- |
| *(OS name)*   | Include this OS in the item's mapping (unchecked = action does not apply) |
| **Execute**   | Whether the action is executed at all on this OS                    |
| **Physical**  | Applies when running on physical hardware                           |
| **Virtual**   | Applies when running in a virtual machine                           |

An OS whose leading checkbox is unchecked is not part of the item's mapping, so the
action does not apply to it. The set of available operating systems is managed globally
via **Manage OS** in the toolbar.

> **Rule:** if both Physical and Virtual are unchecked, Execute is automatically forced off.

---

## Managing OS definitions

Click **Manage OS** to open the OS definitions dialog. This is the global list of operating systems the template supports.

Each OS definition has:

| Field           | Description                                                                         |
| --------------- | ----------------------------------------------------------------------------------- |
| Tag             | Unique XML element name used internally (e.g. `Windows11`)                          |
| Name            | Display name (e.g. `Windows 11`)                                                    |
| Abbreviation    | Short label shown in the OS mapping table; auto-derived from the name if left empty |
| Server OS       | Whether this is a Windows Server edition                                            |
| BuildStartsWith | One or more Windows build number prefixes used to identify this OS at runtime       |

Deleting an OS that is referenced by items will show a confirmation prompt.

---

## Validation

The toolbar's **Download XML** action is disabled when the document has errors. A validation bar at the bottom of the editor shows all current errors and warnings with their location.

Common validation rules:

- Name and type are required on every item
- Registry items must have a hive and path
- ScheduledTask items must have a name and path
- PowerShell items must have a non-empty script
- FileFolder Rename action requires a new name
- OS mapping: Execute cannot be true if both Physical and Virtual are false

---

## PDF export

Click **PDF Report** to export a formatted document listing all items.

Options:

- **OS Filter** — restrict the report to items mapped to a specific OS (or leave as "All OS")
- **Sort By** — order items by their numeric `Order` field or alphabetically by name

The PDF is generated entirely in the browser and downloaded automatically.

---

## XML format

The template XML follows a structured format. Below is a minimal example:

```xml
<WindowsOptimizationTemplate>
  <SupportedOS>
    <Windows11 Name="Windows 11" Abbreviation="W11" IsServerOS="false">
      <BuildStartsWith>226</BuildStartsWith>
    </Windows11>
  </SupportedOS>
  <Registry Name="Disable Telemetry" Description="..." Category="Privacy" Order="100">
    <Hive>HKLM</Hive>
    <Path>SOFTWARE\Policies\Microsoft\Windows\DataCollection</Path>
    <Name>AllowTelemetry</Name>
    <Action>SetValue</Action>
    <Value>0</Value>
    <RegistryType>DWord</RegistryType>
    <Windows11 Execute="true" Physical="true" Virtual="true" />
  </Registry>
</WindowsOptimizationTemplate>
```

---

## Development

```bash
npm install
npm run dev      # start dev server
npm run build    # production build → dist/
npm run test     # run unit tests
```

Built with [Vue 3](https://vuejs.org/), [Vite](https://vitejs.dev/), and [TypeScript](https://www.typescriptlang.org/). No external UI framework.

Deployed automatically to GitHub Pages on every push to `main` via `.github/workflows/deploy.yml`.

---

## White-labeling for forks

The app ships with the **Command Center** layout and the default Workspace Optimizer
branding (name, logo, cyan accent). If you fork this repository to build and host the
app for your own company, you can **override that default branding without changing any
code** — the layout is unchanged, only the brand identity is replaced. Branding is
driven entirely by GitHub Actions **repository Variables** (these are inherited by your
fork and are not secret).

### How to set it up

1. In your fork: **Settings → Secrets and variables → Actions → Variables → New repository variable**.
2. Add any of the variables below (all optional — unset ones keep the defaults).
3. Push to `main` (or run the workflow manually). The next build picks them up.

> **Your branding survives upstream pulls.** Repository Variables are stored in your fork's
> GitHub settings, **not** in the code. Pulling/merging new changes from the upstream
> repository only updates source files — it never touches your Variables, so your branding
> keeps working with zero merge conflicts. Set them once and forget them. (The same is true
> of a `public/brand-logo.png` you commit: upstream never ships a file at that path, so it
> won't conflict.)

| Variable                  | Effect                                                                    | Example                          |
| ------------------------- | ------------------------------------------------------------------------- | -------------------------------- |
| `VITE_BRAND_NAME`         | App name in the navbar, browser tab title, and About dialog               | `Contoso Optimizer`              |
| `VITE_BRAND_VENDOR`       | Your "Distributed by …" line in the About dialog                          | `Contoso IT`                     |
| `VITE_BRAND_URL`          | Your website link in the About dialog                                     | `https://contoso.example`        |
| `VITE_BRAND_DESCRIPTION`  | The description paragraph in the About dialog                             | `Internal Windows tuning tool`   |
| `VITE_BRAND_LOGO_VALUE`   | Logo as a URL, a `data:` URI, or raw base64 (see logo options below)      | `https://contoso.example/l.png`  |
| `VITE_BRAND_ACCENT`       | Accent color as a hex value, applied across both themes                   | `#e11d48`                        |

The same variable names are used everywhere — in your repository Variables, on the command
line, and in `.env.local` — so there is only one name to remember per setting.

### Logo options

The logo is resolved in this order:

1. **`VITE_BRAND_LOGO_VALUE`** repository Variable, if set. It accepts any of:
   - an **http(s) URL** to a hosted image — `https://contoso.example/logo.png`
   - a full **`data:` URI** — `data:image/png;base64,iVBORw0KGgo…`
   - **raw base64** with no prefix — `iVBORw0KGgo…`. The image type (PNG, JPEG,
     GIF, WebP, SVG) is auto-detected from the data's magic bytes and wrapped into
     a `data:` URI for you. This is handy for fully self-contained builds with no
     external image request.
2. **Convention file** — commit your logo to `WorkspaceOptimizer/public/brand-logo.png`.
   It is served at the site root and used automatically.
3. **Bundled default** — the original Workspace Optimizer logo, used if none of the above is present.

The logo is displayed at a fixed height with its width following the image's natural
aspect ratio (capped so it never crowds the app title), so non-square logos render
correctly. The convention file or an embedded base64 value is recommended for
self-hosting since neither has an external dependency.

### Attribution

White-labeling changes the displayed product name, your vendor line, links, description,
accent color, and logo. The original author credit — **John Billekens Consultancy & AppVentiX** —
always remains visible in the About dialog, and a small "Powered by Workspace Optimizer"
line appears when the app has been rebranded. Your own vendor line is shown **in addition
to**, not instead of, the original credit. Please keep this attribution intact.

### Local testing

Branding is read at **build time** from the `VITE_BRAND_*` environment variables — the same
names you use as repository Variables. There are two ways to set them locally.

**Option A — `.env.local` file (recommended).** Create `WorkspaceOptimizer/.env.local`:

```bash
# WorkspaceOptimizer/.env.local   (git-ignored — never committed)
VITE_BRAND_NAME=Contoso Optimizer
VITE_BRAND_VENDOR=Contoso IT
VITE_BRAND_ACCENT=#e11d48
```

Then run `npm run dev` or `npm run build` from `WorkspaceOptimizer/`.

**Option B — command-line variables.** Set the variables in the shell **before** starting
the dev server or build (Vite reads them when the process starts; setting them after the
server is already running has no effect).

PowerShell:

```powershell
cd WorkspaceOptimizer
$env:VITE_BRAND_NAME   = "Contoso Optimizer"
$env:VITE_BRAND_VENDOR = "Contoso IT"
$env:VITE_BRAND_ACCENT = "#e11d48"
npm run dev          # or: npm run build
```

Bash / macOS / Linux:

```bash
cd WorkspaceOptimizer
VITE_BRAND_NAME="Contoso Optimizer" \
VITE_BRAND_VENDOR="Contoso IT" \
VITE_BRAND_ACCENT="#e11d48" \
npm run dev          # or: npm run build
```

> The logo is **not** changed by `VITE_BRAND_NAME`/`VITE_BRAND_ACCENT` alone. To preview a
> branded logo locally, also set `VITE_BRAND_LOGO_VALUE=...` (a URL, `data:` URI, or raw
> base64) or drop a file at `WorkspaceOptimizer/public/brand-logo.png`.