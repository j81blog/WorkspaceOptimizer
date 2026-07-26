# Contributing

Thanks for considering a contribution. This guide covers Marketplace submissions, which
have their own review process because they end up running against real machines.

For code changes, the short version is: `npm run test` and `npm run build` from
`WorkspaceOptimizer/`, then open a PR.

---

## Submitting a template or snippet

**Snippet**: a reusable group of items, merged into whatever the user already has open.
**Template**: a complete document that replaces the user's current one.

If you are contributing a handful of related tweaks, it is a snippet.

### 1. Build it in the editor

Easiest route: open the app, build what you want, then **Download XML**. Templates
downloaded from the editor already have the structure and metadata the catalog needs.

Fill in **Properties** before downloading. `Name`, `Description` and `Author` are
required, and the `Id` is generated for you.

### 2. Put the file in the right folder

```
WorkspaceOptimizer/public/marketplace/template/    complete templates
WorkspaceOptimizer/public/marketplace/snippet/     reusable groups of items
```

### 3. Regenerate the catalog

```bash
cd WorkspaceOptimizer
npm run catalog:sync
```

This rewrites `public/marketplace/index.json` from your file's `<Metadata>` block. Commit
the result. CI fails if the catalog and the files disagree.

### 4. Check what it would do

```bash
npm run review:submission
```

This prints every PowerShell script, file deletion and sensitive registry key your
submission contains. It is not a pass/fail gate, since deleting files and running scripts
are legitimate here, but whatever it flags is what a reviewer will ask about, so read it
first.

### 5. Open the PR

Use the matching template by appending it to the compare URL:

```
?template=marketplace-snippet.md
?template=marketplace-template.md
```

---

## What reviewers look for

Every submission is read by a person before it merges. In rough order of importance:

**Does it do what it says?** The description should match the items. A snippet called
"Disable Telemetry" that also disables Defender will be sent back.

**Is it reversible, and does the PR say so?** Someone applying this should know what they
are committing to. `DeleteKeyRecursively` and file deletions deserve an explicit note.

**Has it been run?** Applied on a real machine or VM, not just opened in the editor. Say
which Windows versions.

**Are the OS mappings honest?** An item mapped to Server 2022 should have been tried
there, or not claim it.

**Anything flagged by `review:submission`.** PowerShell that downloads and executes remote
content is the highest bar. Expect to justify it, and expect a preference for doing the
same thing with a registry or service item instead.

### Things that will not be merged

- Scripts that fetch and execute remote content without a very good reason
- Tweaks that disable security features without saying so plainly
- Submissions copied from elsewhere without attribution
- Anything the author has not actually run

---

## Local development

```bash
cd WorkspaceOptimizer
npm install
npm run dev                # dev server
npm run test               # unit tests
npm run build              # type-check, validate the catalog, build
npm run validate:catalog   # catalog and variable checks on their own
npm run catalog:sync       # regenerate index.json from the XML files
npm run catalog:check      # fail if index.json is out of date
npm run review:submission  # summarize what marketplace files would do
```

CI runs the catalog checks, the type check, the tests and the build on every pull request.
