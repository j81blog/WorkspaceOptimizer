---
name: Marketplace template
about: Add a complete template to the Marketplace
labels: marketplace, template
---

## What is this template for?

<!-- The scenario it targets: VDI golden image, kiosk, developer workstation… -->

**Source of these tweaks:** <!-- your own testing, vendor documentation, a public guide (link it) -->

> Loading a template **replaces** whatever the user has open, so it should stand on its own
> as a complete starting point rather than a handful of tweaks. If it is a handful of
> tweaks, submit it as a snippet instead.

## Checklist

- [ ] The file is in `WorkspaceOptimizer/public/marketplace/template/`
- [ ] `<Metadata>` has `Id` (a GUID), `Name`, `Description` and `Author`
- [ ] `<SupportedOS>` lists every OS the template targets, with build numbers
- [ ] Items use meaningful categories and sensible `Order` values
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
- [ ] The machine was still usable afterwards (network, login, updates)

**Windows versions tested:** <!-- e.g. Windows 11 24H2, Server 2022 -->
**Roughly how many items:** <!-- the CI summary prints the exact count -->

## Reversibility

<!-- Which changes are hard to undo? Anyone applying a whole template to a machine
     should know what they are committing to. -->

## Anything that needs a closer look?

<!-- PowerShell scripts, file deletions, policy or Defender keys, or anything that
     affects security. Say so here, the CI summary will flag them anyway, and
     explaining why up front makes review much faster.

     If this template contains none of those, say "none". -->
