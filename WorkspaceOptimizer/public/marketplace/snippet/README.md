# Snippets

Reusable groups of items published through the Marketplace. Importing one **merges** its
items into the template currently open, after a review step, rather than replacing it.

A snippet is an ordinary Workspace Optimizer XML file with fewer items: the same
`<Items>` root, just a handful of `<Item>` elements.

## Publishing one

1. Put the `.xml` file in this folder.
2. Describe it in the file's own `<Metadata>` block.
3. Run `npm run catalog:sync` from `WorkspaceOptimizer/` to regenerate `../index.json`.

```xml
<Metadata>
  <Version>1.0.0</Version>
  <SchemaVersion>1</SchemaVersion>
  <Id>3f2b1a90-4c7d-4e11-9a52-8b6c0d1e2f34</Id>
  <Name>Disable Telemetry</Name>
  <Description>Turns off diagnostic data collection.</Description>
  <Author>Your Name</Author>
  <Category>Privacy</Category>
  <Tags>
    <Tag>privacy</Tag>
    <Tag>telemetry</Tag>
  </Tags>
</Metadata>
```

`Name`, `Description` and `Author` are required. The editor will not let a template be
downloaded without them, and the **Properties** dialog writes exactly these fields.
`Category` and `Tags` are optional.

`itemCount` is counted from the file, so it never goes stale. Leave `<Id>` out and the
sync generates a GUID. Copy it back into the file to keep the entry id stable.

Editing `../index.json` by hand still works; `npm run catalog:check` tells you when it no
longer matches the files, and CI fails on the same check.

## Include a `<SupportedOS>` block

It is optional, but include one for every OS your items reference. When an item targets an
OS the user's template does not define, the import offers to add it, and can only fill in
the build numbers if the snippet supplied them. Without a definition the OS is still
offered, but arrives disabled until the user completes it in **Options → Manage OS**.

```xml
<SupportedOS>
  <OS>
    <Tag>Windows11</Tag>
    <Name>Windows 11</Name>
    <Abbreviation>W11</Abbreviation>
    <ServerOS>0</ServerOS>
    <Builds><BuildStartsWith>22</BuildStartsWith></Builds>
  </OS>
</SupportedOS>
```

See the README section [Marketplace](../../../../README.md#marketplace) for the full
catalog format.
