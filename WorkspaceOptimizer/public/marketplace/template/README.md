# Templates

Full templates published through the Marketplace. Loading one **replaces** the document
currently open in the editor.

A template is an ordinary Workspace Optimizer XML file: an `<Items>` root with a
`<SupportedOS>` block and one `<Item>` per action. Export one from the editor with
**Download XML** and drop it in here.

## Publishing one

1. Put the `.xml` file in this folder.
2. Describe it in the file's own `<Metadata>` block.
3. Run `npm run catalog:sync` from `WorkspaceOptimizer/` to regenerate `../index.json`.

```xml
<Metadata>
  <Version>1.0.0</Version>
  <SchemaVersion>1</SchemaVersion>
  <Id>9d4e5f60-1a2b-4c3d-8e7f-0a1b2c3d4e5f</Id>
  <Name>VDI Baseline</Name>
  <Description>Starting point for non-persistent VDI images.</Description>
  <Author>Your Name</Author>
  <Category>Baseline</Category>
  <Tags>
    <Tag>vdi</Tag>
  </Tags>
</Metadata>
```

`Name`, `Description` and `Author` are required. The editor will not let a template be
downloaded without them, and the **Properties** dialog writes exactly these fields.
`Category` and `Tags` are optional.

`itemCount` is counted from the file, so it never goes stale. Leave `<Id>` out and the
sync generates a GUID. Copy it back into the file to keep the entry id stable.

`npm run build` validates this folder and fails on a broken or missing file, malformed
JSON or a duplicate `id`. CI additionally runs `npm run catalog:check`, which fails when
`index.json` no longer matches the files.

The default template is **not** stored here. It lives at `public/Windows.xml` and the
catalog refers to it as `../Windows.xml`, so there is only ever one copy of it.

See the README section [Marketplace](../../../../README.md#marketplace) for the full
catalog format.
