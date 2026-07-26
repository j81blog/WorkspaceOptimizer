# Workspace Optimizer

Browser-based editor for Windows optimization template. Load, edit, validate, and export XML templates that drive registry, service, scheduled task, app removal, PowerShell, and file/folder actions across multiple Windows OS versions. No install, no backend. It runs entirely in your browser.

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

Open the app at the link above. It starts with an empty editor, and everything you need to
begin is under **Options**:

- **New from Default** loads the built-in `Windows.xml`, the quickest way to see a real example.
- **New template** starts an empty document, ready for your own items.
- **Open template…** loads a `.xml` file from your computer.

The first two also have their own toolbar buttons. Adding items is only possible once a
template is open.

---

## Interface overview

The app uses a **Command Center** layout: a horizontal **toolbar** across the top
holds the brand and every global action, below it on the left is the **item list
(explorer)**, and the rest of the window is the focused **item editor**.

```
┌──────────────────────────────────────────────────────────────┐
│ Toolbar: logo · brand │ actions… │ filename · ● Modified · ☾ │
├──────────────┬───────────────────────────────────────────────┤
│              │                                               │
│  Item list   │  Item editor                                  │
│  (explorer)  │  (General + Payload | OS Mapping)             │
│              │                                               │
│              ├───────────────────────────────────────────────┤
│              │  Validation bar                               │
│              │                                               │
└──────────────┴───────────────────────────────────────────────┘
```

> This Command Center layout is the **default look with no configuration**. A fork can
> restyle the brand (name, logo, accent color) on top of it via repository Variables.
> See [White-labeling for forks](#white-labeling-for-forks). Branding overrides the
> appearance; the layout stays the same.

### Toolbar actions

The horizontal toolbar holds the brand on the left and every global action as a
labeled button; the current filename, a **Modified** indicator, and the theme toggle
sit on the right.

| Button               | Action                                                                               |
| -------------------- | ------------------------------------------------------------------------------------ |
| **Options**          | Every template action in one menu (see below)                                         |
| **New from Default** | Reset to the built-in default template                                               |
| **Open Template**    | Load a `.xml` template file from disk, edit your own template                         |
| **Download XML**     | Save the current template as an XML file (disabled when there are validation errors)  |
| **Download Script**  | Save the latest PowerShell script, to apply the optimization                          |
| **Properties**       | Edit the template's name, description, author and tags (see [Template Properties](#template-properties)) |
| **About**            | Open the About dialog (versions, credits, What's New)                                 |
| **☾ / ☀**           | Toggle dark/light theme (remembers your preference)                                   |

**Properties** turns red while a required field is missing.

#### The Options menu

| Entry | Action |
| --- | --- |
| **New template** | Start empty and build from scratch. The OS list comes from the built-in template |
| **New from default** | Load the built-in template (same as the toolbar button) |
| **Open template…** | Load a `.xml` file from disk (same as the toolbar button) |
| **Add from… → Marketplace** | Browse the [Marketplace](#marketplace) |
| **Add from… → Import .reg file** | Run the [`.reg` import wizard](#importing-reg-files) |
| **Manage OS** | Add, edit, or remove OS definitions |
| **PDF report** | Export a formatted PDF overview of all items |

**Manage OS** and **PDF report** are in this menu only. **Add from…** disappears when both
import routes are disabled for the build, and the entries that need an open document are
greyed out until there is one.

The right side of the toolbar shows the current filename and a yellow **Modified**
indicator when there are unsaved changes.

### Sidebar

Lists all items in the template. You can:

- **Search** by name, description, or category using the search box
- **Filter** by category, type, or OS using the dropdowns
- **Sort** by category grouping or numeric order
- **Add**, **Duplicate** or **Delete** an item with the buttons at the top
- **Select an item** to open it in the editor

Each item row shows its type icon, name, category, and which OS versions it is mapped to.

### Item editor

Editing area for the selected item, split into two columns:

- **Left column**: General fields (name, description, type, category, order) and the type-specific payload
- **Right column**: OS Mapping table

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

The OS Mapping lists every OS the template supports, grouped into **Client OS**
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
via **Options → Manage OS**.

> **Rule:** if both Physical and Virtual are unchecked, Execute is automatically forced off.

---

## Managing OS definitions

Choose **Options → Manage OS** to open the OS definitions dialog. This is the global list of operating systems the template supports.

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

- The template's Name, Description and Author are required (see [Template Properties](#template-properties))
- Name and type are required on every item
- Registry items must have a hive and path
- ScheduledTask items must have a name and path
- PowerShell items must have a non-empty script
- FileFolder Rename action requires a new name
- OS mapping: Execute cannot be true if both Physical and Virtual are false

---

## PDF export

Choose **Options → PDF report** to export a formatted document listing all items.

Options:

- **OS Filter**: restrict the report to items mapped to a specific OS (or leave as "All OS")
- **Sort By**: order items by their numeric `Order` field or alphabetically by name

The PDF is generated entirely in the browser and downloaded automatically.

---

## XML format

The template XML follows a structured format. Every field is an element, never an
attribute. The root is `<Items>`, each action is an `<Item>`, and the payload element
is named after the item's `<Type>`. Below is a minimal but complete example:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Items>
  <Metadata>
    <Version>2026.429.2230</Version>
    <SchemaVersion>1</SchemaVersion>
    <Id>7aa42628-955f-4112-bcc7-837faa2fdd32</Id>
    <Name>Example Template</Name>
    <Description>A minimal template with a single registry tweak.</Description>
    <Author>Your Name</Author>
    <Category>Privacy</Category>
    <Tags>
      <Tag>privacy</Tag>
    </Tags>
  </Metadata>
  <SupportedOS>
    <OS>
      <Tag>Windows11</Tag>
      <Name>Windows 11</Name>
      <Abbreviation>W11</Abbreviation>
      <ServerOS>0</ServerOS>
      <Builds>
        <BuildStartsWith>22</BuildStartsWith>
        <BuildStartsWith>26</BuildStartsWith>
      </Builds>
    </OS>
  </SupportedOS>
  <Item>
    <Name>Disable Telemetry</Name>
    <Description>Turns off diagnostic data collection.</Description>
    <Type>Registry</Type>
    <Category>Privacy</Category>
    <Order>100</Order>
    <OS>
      <Windows11>
        <Execute>1</Execute>
        <Physical>1</Physical>
        <Virtual>1</Virtual>
      </Windows11>
    </OS>
    <Registry>
      <Hive>HKLM</Hive>
      <Name>AllowTelemetry</Name>
      <Path>SOFTWARE\Policies\Microsoft\Windows\DataCollection</Path>
      <Action>SetValue</Action>
      <Value>0</Value>
      <Type>DWord</Type>
    </Registry>
  </Item>
</Items>
```

Notes:

- `<Metadata>` describes the template. `Name`, `Description` and `Author` are required
  before the XML can be downloaded, `Id` is generated for you, and `Category` and `Tags`
  are optional. Edit them all under **Properties** (see
  [Template Properties](#template-properties)). `<Version>` is re-stamped as
  `yyyy.Mdd.Hmm` whenever you download a template with unsaved changes.
- Metadata tags are nested under `<Tags>`, because `SupportedOS` entries use a `<Tag>`
  element of their own.
- Booleans are `1` / `0`, not `true` / `false`.
- An OS tag is listed under an item's `<OS>` only when that item supports it. Omitting
  the tag means "not supported", which is different from `<Execute>0</Execute>`.
- The `<Tag>` value becomes the element name in each item's `<OS>` block, so it must be
  a valid XML element name.

---

## Marketplace

The Marketplace browses a catalog of ready-made **templates** (a whole document, which
replaces what you have open) and **snippets** (a handful of items, merged into your current
template after review).

Open it from **Options → Add from… → Marketplace**.

> Want to contribute a template or snippet? See [CONTRIBUTING.md](CONTRIBUTING.md). Every
> submission is reviewed by a person, and `npm run review:submission` shows you what a
> reviewer will be asked about.

The app ships with an empty catalog at `public/marketplace/index.json`, so the feature is
always available. Point the `VITE_MARKETPLACE_URL` repository Variable at your own
`index.json` to replace it, or edit the bundled file to publish a catalog alongside your
own deployment.

### Marketplace options

All four are optional repository Variables (or `.env.local` entries when testing locally).

| Variable | Effect |
| --- | --- |
| `VITE_MARKETPLACE_URL` | One or more catalog URLs, **added to** the bundled catalog. |
| `VITE_MARKETPLACE_DISABLE_BUNDLED` | `true` drops the bundled catalog, leaving only the URLs above. |
| `VITE_MARKETPLACE_TRUSTED_HOSTS` | Hosts whose content imports without a confirmation prompt. Bare hosts or full URLs both work. |
| `VITE_DISABLE_MARKETPLACE` | `true` removes the Marketplace entry from the **Add from…** menu. |
| `VITE_DISABLE_REG_IMPORT` | `true` removes the **Import .reg file** entry. |

Disabling both import routes hides the **Add from…** button entirely, which is the way to
ship a build with no import routes at all.

#### Hosting your own build

The bundled catalog at `public/marketplace/index.json` is a file in the repository, so a
fork inherits whatever it contains. Configured catalogs are **added to** it rather than
replacing it, which gives three combinations:

| You want | Set |
| --- | --- |
| Only your own catalogs | `VITE_MARKETPLACE_URL` **and** `VITE_MARKETPLACE_DISABLE_BUNDLED=true` |
| Your catalogs plus the bundled one | `VITE_MARKETPLACE_URL` |
| Only the bundled one | nothing |
| No Marketplace at all | `VITE_DISABLE_MARKETPLACE=true` |

`VITE_MARKETPLACE_DISABLE_BUNDLED` ignores the bundled file regardless of what it
contains, so upstream catalog entries can never reappear in your deployment through a
merge. Editing or emptying the file works too, but the flag survives merges without
creating a conflict, the same reasoning as the branding Variables.

Setting that flag without a `VITE_MARKETPLACE_URL` would leave nothing to load at all, so
the build fails with a message pointing at the two sensible fixes: name a catalog, or turn
the Marketplace off with `VITE_DISABLE_MARKETPLACE=true`.

**List syntax.** `VITE_MARKETPLACE_URL` and `VITE_MARKETPLACE_TRUSTED_HOSTS` accept
several values separated by a **comma, semicolon or newline**. Spaces are deliberately
not separators: a value containing one is far more likely to be a typo than two entries,
so the build rejects it rather than quietly splitting `a.example.com b.example.com` into
two hosts.

#### Several catalogs at once

```
VITE_MARKETPLACE_URL=https://raw.githubusercontent.com/you/catalog/main/index.json,
                     https://raw.githubusercontent.com/team/shared/main/index.json
```

Catalogs load in parallel and their entries are merged into one list, together with the
bundled catalog unless `VITE_MARKETPLACE_DISABLE_BUNDLED` is set. When more than one is in
play, each entry shows which catalog it came from.

Two catalogs may use the same entry `id`. Both are listed rather than one silently
shadowing the other, and a warning names the clashing ids so you can tell them apart by
their source. If a catalog fails to load, the others still work and a banner reports which
one failed and why.

#### Trusted hosts

```
VITE_MARKETPLACE_TRUSTED_HOSTS=raw.githubusercontent.com, cdn.contoso.example
```

Content from a listed host imports without the external-content confirmation, the same as
content served from the app's own origin. Everything else still requires an explicit
acknowledgement. Only add hosts you control or genuinely trust: a trusted catalog can
import items that change registry values, disable services and delete files.

#### Build-time validation

The build validates the bundled catalog and these variables, and fails on anything
malformed. See [What the build validates](#what-the-build-validates).

Remote catalogs are fetched by the browser at runtime, so the build cannot inspect their
contents; cross-catalog id clashes surface as a warning in the dialog instead.

### Importing a snippet

Snippet items are never merged blindly. The preview lists every incoming item with a status:

| Status | Meaning | Selected by default |
| --- | --- | --- |
| **New** | Nothing in your template targets the same registry value, service, task, app or path | Yes |
| **Duplicate** | An existing item targets the same thing with an identical payload, so importing would change nothing | No |
| **Conflict** | An existing item targets the same thing with a *different* payload, so importing adds a second item and the higher `Order` wins at deploy time | No |

Identity is based on what an item *targets*, not its name, so a renamed copy of an existing
tweak is still recognized as a duplicate.

**Category and deploy order are editable in the preview.** A snippet author picks both
without knowing your template, so the fields above the table apply one value to every
selected item, and each row can be adjusted individually. Item names stay as the snippet's
author wrote them. The `.reg` wizard additionally lets you edit names, since a `.reg` file
supplies none.

An item's category comes from its own `<Category>` element; if it has none, the file's
`<Metadata><Category>` is used, and failing that the placeholder `Imported`. A category is
always set, because the validator requires one.

If a snippet references an operating system your template does not define, the preview
offers to add that OS when the snippet carries its definition, and otherwise warns that the
mapping will be dropped. Either way the merge cannot leave your template with a dangling OS
reference.

### Hosting your own catalog

The catalog is a single JSON file. Entry `url` values may be absolute, or relative to the
index itself.

```jsonc
{
  "schemaVersion": 1,
  "name": "Contoso Catalog",
  "updated": "2026-07-25",
  "entries": [
    {
      "id": "contoso.telemetry",     // required, stable, unique
      "kind": "snippet",             // required: "template" or "snippet"
      "name": "Disable Telemetry",   // required
      "url": "snippets/tel.xml",     // required: absolute, or relative to this file
      "description": "Turns off diagnostic data collection.",
      "version": "1.2.0",
      "author": "Contoso IT",
      "category": "Privacy",
      "tags": ["privacy", "telemetry"],
      "itemCount": 7
    }
  ]
}
```

Only `id`, `kind`, `name` and `url` are required; everything else is display metadata.
Entries missing a required field, or using an unrecognized `kind`, are skipped rather than
breaking the catalog.

A snippet file is just a normal template XML with fewer items. Include `<SupportedOS>` for
any OS your items reference, so the importer can offer to add it.

### Template Properties

**Properties** in the toolbar edits the descriptive fields that go into the file's
`<Metadata>` block. **Name**, **Description** and **Author** are required: a marketplace
catalog is generated from them, so the XML cannot be downloaded until they are set. The
validation bar lists whatever is missing, clicking the message opens the dialog, and the
Properties button turns red while anything is outstanding.

An **Id** is generated automatically and kept for the life of the template, so entries stay
stable across catalog regenerations. Only use **New** for a template split off from another
that needs its own identity. **Category** and **Tags** are optional. **Version** is
re-stamped on download whenever the document has unsaved changes.

### Generating the catalog from your files

You do not have to write `index.json` by hand. Put the descriptive fields in each file's
`<Metadata>` block (the Properties dialog writes exactly these) and generate the catalog
from them:

```xml
<Metadata>
  <Version>2026.429.2230</Version>
  <SchemaVersion>1</SchemaVersion>
  <Id>7aa42628-955f-4112-bcc7-837faa2fdd32</Id>
  <Name>Default Template</Name>
  <Description>The built-in Windows cleanup and optimization template.</Description>
  <Author>John Billekens Consultancy</Author>
  <Category>Baseline</Category>
  <Tags>
    <Tag>performance</Tag>
    <Tag>optimization</Tag>
  </Tags>
</Metadata>
```

`Name`, `Description` and `Author` are required before the XML can be downloaded. `Id` is
generated for you, and `Category` and `Tags` are optional. Metadata tags are nested under
`<Tags>` because `SupportedOS` entries use a `<Tag>` element of their own.

The block is metadata for this editor and the catalog only:
`Invoke-WindowsOptimization.ps1` reads the `<Item>` elements and ignores it entirely.

Drop `.xml` files into `public/marketplace/template/` or `public/marketplace/snippet/`,
then:

```bash
npm run catalog:sync     # rewrite index.json from the files
npm run catalog:check    # report whether it is out of date, without changing it
```

`itemCount` is counted from the file, `version` comes from `<Version>`, and `updated` is
set to today. A file with no `<Id>` gets a fresh GUID; copy it into the file's
`<Metadata>` so the entry id stays stable the next time you sync.

**The build never rewrites the catalog.** It only validates, so what deploys is always
exactly what is committed. CI runs `catalog:check` and fails if the two have drifted,
which catches a forgotten `catalog:sync`.

### What the build validates

`npm run build` runs `npm run validate:catalog` first and fails on:

- malformed `index.json`, an unsupported `schemaVersion`, a missing required field, or a duplicate entry `id`
- an entry whose `url` points at a file that does not exist, or that is not a template
- a syntactically invalid variable (see [Marketplace options](#marketplace-options))

It warns, without failing, when an `itemCount` is stale, when a snippet has no
`<SupportedOS>` block, or when an XML file in those folders is not referenced by any
entry. Run it on its own at any time:

```bash
npm run validate:catalog
```

> **The host must send `Access-Control-Allow-Origin`.** `raw.githubusercontent.com` sends
> `*`, which makes a plain GitHub repository the simplest place to host a catalog. GitHub
> Pages does **not** send it by default, so a catalog served from a Pages site will fail to
> load.

### Trust

Content loaded from a different origin than the app itself requires an explicit
acknowledgement before it can be imported. Imported items can change registry values,
disable services and delete files. Content served from the same origin as the app is treated
as trusted.

Separately, items that arrived from the Marketplace or a `.reg` import are remembered for the
session, and downloading a template containing any of them shows a summary first. That
tracking is in-memory only and is never written into the XML.

---

## Importing .reg files

**Add from… → Import .reg file** turns a Registry Editor export into template items.

1. **File.** Pick the `.reg` file. Files exported by `regedit` are UTF-16LE; that is detected
   and decoded automatically, as are UTF-8 and BOM-less variants.
2. **Defaults.** Choose the category (required), the deploy order, and which operating
   systems the imported items should run on. Parser warnings are listed here.
3. **Review.** Every value appears as an editable row. Adjust names, categories and orders,
   and untick anything you do not want.

### Supported syntax

| `.reg` | Imported as |
| --- | --- |
| `"Name"="text"` | String |
| `"Name"=dword:0000001f` | DWord, converted to decimal (`31`) |
| `"Name"=hex:de,ad` | Binary |
| `"Name"=hex(2):…` | ExpandString |
| `"Name"=hex(7):…` | MultiString, one value per line |
| `"Name"=hex(b):…` | Qword (full 64-bit precision) |
| `"Name"=hex(4):…` | DWord (little-endian) |
| `@="text"` | The key's default value |
| `"Name"=-` | DeleteValue |
| `[-HKEY_…\Key]` | DeleteKeyRecursively |

Both `Windows Registry Editor Version 5.00` and `REGEDIT4` headers are accepted, as are
backslash line continuations, `;` comments, and escaped `\\` and `\"` inside strings.

### Limitations

- `HKEY_CLASSES_ROOT` is rewritten to `HKLM\SOFTWARE\Classes`, which is the machine-wide
  half of that merged view. A warning shows each rewrite.
- `HKEY_USERS\.DEFAULT` maps to the `HKU\DefaultUser` hive.
- `HKEY_CURRENT_CONFIG` is not supported and is skipped with a warning.
- Resource-list types (`hex(8)`, `hex(9)`, `hex(a)`) are skipped.
- `[-Key]` becomes `DeleteKeyRecursively`, matching what `regedit` actually does. Those rows
  are flagged in the review step so you can downgrade them to a non-recursive `DeleteKey`.
- A `.reg` file carries no OS, description or ordering information; the wizard supplies those.
- Maximum file size is 5 MB, and at most 2000 values per import.

---

## Development

```bash
npm install
npm run dev                # start dev server
npm run build              # type-check, validate the catalog, production build → dist/
npm run preview            # serve the production build locally
npm run test               # run unit tests
npm run test:watch         # re-run tests on change
npm run validate:catalog   # check the marketplace catalog and variables
npm run catalog:sync       # regenerate index.json from the XML files
npm run catalog:check      # fail if index.json is out of date
npm run review:submission  # summarize what marketplace files would do to a machine
```

Built with [Vue 3](https://vuejs.org/), [Vite](https://vitejs.dev/), and [TypeScript](https://www.typescriptlang.org/). No external UI framework.

Deployed automatically to GitHub Pages on every push to `main` via
`.github/workflows/deploy.yml`. CI runs the tests and `catalog:check` before building, so a
failing test or a stale catalog blocks the deploy.

---

## White-labeling for forks

The app ships with the **Command Center** layout and the default Workspace Optimizer
branding (name, logo, cyan accent). If you fork this repository to build and host the
app for your own company, you can **override that default branding without changing any
code**. The layout is unchanged, only the brand identity is replaced. Branding is
driven entirely by GitHub Actions **repository Variables** (these are inherited by your
fork and are not secret).

### How to set it up

1. In your fork: **Settings → Secrets and variables → Actions → Variables → New repository variable**.
2. Add any of the variables below (all optional, unset ones keep the defaults).
3. Push to `main` (or run the workflow manually). The next build picks them up.

> **Your branding survives upstream pulls.** Repository Variables are stored in your fork's
> GitHub settings, **not** in the code. Pulling/merging new changes from the upstream
> repository only updates source files. It never touches your Variables, so your branding
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
| `VITE_BRAND_REPO_URL`     | Source repository, linked from an empty Marketplace. Unset links the upstream project; `none` shows no link | `https://github.com/you/fork`    |
| `VITE_MARKETPLACE_URL`    | One or more catalog URLs, added to the bundled one (see [Marketplace options](#marketplace-options)) | `https://raw.githubusercontent.com/you/catalog/main/index.json` |
| `VITE_MARKETPLACE_DISABLE_BUNDLED` | `true` ignores the bundled catalog, leaving only your own    | `true`                           |
| `VITE_MARKETPLACE_TRUSTED_HOSTS` | Hosts that import without a confirmation prompt          | `raw.githubusercontent.com`      |
| `VITE_DISABLE_MARKETPLACE` | `true` removes the Marketplace from the Add from… menu                  | `true`                           |
| `VITE_DISABLE_REG_IMPORT` | `true` removes .reg import from the Add from… menu                      | `true`                           |

The same variable names are used everywhere (in your repository Variables, on the command
line, and in `.env.local`), so there is only one name to remember per setting.

### Logo options

The logo is resolved in this order:

1. **`VITE_BRAND_LOGO_VALUE`** repository Variable, if set. It accepts any of:
   - an **http(s) URL** to a hosted image: `https://contoso.example/logo.png`
   - a full **`data:` URI**: `data:image/png;base64,iVBORw0KGgo…`
   - **raw base64** with no prefix: `iVBORw0KGgo…`. The image type (PNG, JPEG,
     GIF, WebP, SVG) is auto-detected from the data's magic bytes and wrapped into
     a `data:` URI for you. This is handy for fully self-contained builds with no
     external image request.
2. **Convention file**: commit your logo to `WorkspaceOptimizer/public/brand-logo.png`.
   It is served at the site root and used automatically.
3. **Bundled default**: the original Workspace Optimizer logo, used if none of the above is present.

The logo is displayed at a fixed height with its width following the image's natural
aspect ratio (capped so it never crowds the app title), so non-square logos render
correctly. The convention file or an embedded base64 value is recommended for
self-hosting since neither has an external dependency.

### Attribution

White-labeling changes the displayed product name, your vendor line, links, description,
accent color, and logo. The original author credit, **John Billekens Consultancy & AppVentiX**,
always remains visible in the About dialog, and a small "Powered by Workspace Optimizer"
line appears when the app has been rebranded. Your own vendor line is shown **in addition
to**, not instead of, the original credit. Please keep this attribution intact.

### Local testing

Branding is read at **build time** from the `VITE_BRAND_*` environment variables, the same
names you use as repository Variables. There are two ways to set them locally.

**Option A: `.env.local` file (recommended).** Create `WorkspaceOptimizer/.env.local`:

```bash
# WorkspaceOptimizer/.env.local   (git-ignored, never committed)
VITE_BRAND_NAME=Contoso Optimizer
VITE_BRAND_VENDOR=Contoso IT
VITE_BRAND_ACCENT=#e11d48
VITE_MARKETPLACE_URL=https://raw.githubusercontent.com/you/catalog/main/index.json
```

Then run `npm run dev` or `npm run build` from `WorkspaceOptimizer/`.

**Option B: command-line variables.** Set the variables in the shell **before** starting
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