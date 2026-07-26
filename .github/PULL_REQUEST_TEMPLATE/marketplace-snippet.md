---
name: Marketplace snippet
about: Add a reusable group of items to the Marketplace
labels: marketplace, snippet
---

## What does this snippet do?

<!-- What it changes, and why someone would want it. -->

**Source of these tweaks:** <!-- your own testing, vendor documentation, a public guide (link it) -->

## Checklist

- [ ] The file is in `WorkspaceOptimizer/public/marketplace/snippet/`
- [ ] `<Metadata>` has `Id` (a GUID), `Name`, `Description` and `Author`
- [ ] It has a `<SupportedOS>` block for every OS the items reference
- [ ] Every item has a meaningful `Category`, not the `Imported` placeholder
- [ ] I ran `npm run catalog:sync` and committed the updated `index.json`
```Text
< Enter your evidence here >
```
- [ ] I ran `npm run review:submission` and read what it flagged
```Text
< Enter your evidence here >
```

## Testing

- [ ] I applied this on a real machine or VM, not only in the editor
- [ ] I imported it in the app and the preview showed no unexpected items

**Windows versions tested:** <!-- e.g. Windows 11 24H2, Server 2022 -->

## Reversibility

<!-- Can a user undo these changes, and how? A reader should know what they are
     committing to before they run it. -->

## Anything that needs a closer look?

<!-- PowerShell scripts, file deletions, policy or Defender keys, or anything that
     affects security. Say so here, the CI summary will flag them anyway, and
     explaining why up front makes review much faster.

     If this snippet contains none of those, say "none". -->
