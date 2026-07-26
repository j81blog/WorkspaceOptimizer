import type { TemplateDocument, ItemPayload } from './types'

export function serializeXml(doc: TemplateDocument): string {
  const lines: string[] = ['<?xml version="1.0" encoding="utf-8"?>', '<Items>']

  // Metadata, only when the source carried one. Descriptive fields are written only
  // when set, so a file that never had them does not gain empty elements.
  if (doc.metadata) {
    const m = doc.metadata
    lines.push('  <Metadata>')
    lines.push(`    <Version>${esc(m.version)}</Version>`)
    lines.push(`    <SchemaVersion>${esc(m.schemaVersion)}</SchemaVersion>`)
    if (m.id) lines.push(`    <Id>${esc(m.id)}</Id>`)
    if (m.name) lines.push(`    <Name>${esc(m.name)}</Name>`)
    if (m.description) lines.push(`    <Description>${esc(m.description)}</Description>`)
    if (m.author) lines.push(`    <Author>${esc(m.author)}</Author>`)
    if (m.category) lines.push(`    <Category>${esc(m.category)}</Category>`)
    if (m.tags.length) {
      lines.push('    <Tags>')
      for (const t of m.tags) lines.push(`      <Tag>${esc(t)}</Tag>`)
      lines.push('    </Tags>')
    }
    lines.push('  </Metadata>')
  }

  // SupportedOS
  lines.push('  <SupportedOS>')
  for (const os of doc.supportedOs) {
    lines.push('    <OS>')
    lines.push(`      <Tag>${esc(os.tag)}</Tag>`)
    lines.push(`      <Name>${esc(os.name)}</Name>`)
    lines.push(`      <Abbreviation>${esc(os.abbreviation)}</Abbreviation>`)
    lines.push(`      <ServerOS>${os.isServerOs ? '1' : '0'}</ServerOS>`)
    lines.push('      <Builds>')
    for (const b of os.buildStartsWith) {
      lines.push(`        <BuildStartsWith>${esc(b)}</BuildStartsWith>`)
    }
    lines.push('      </Builds>')
    lines.push('    </OS>')
  }
  lines.push('  </SupportedOS>')

  // Items, sorted by Order asc, then Name A-Z
  const sorted = [...doc.items].sort((a, b) =>
    a.order - b.order || a.name.toLowerCase().localeCompare(b.name.toLowerCase())
  )

  for (const item of sorted) {
    lines.push('  <Item>')
    lines.push(`    <Name>${esc(item.name)}</Name>`)
    lines.push(`    <Description>${esc(item.description)}</Description>`)
    lines.push(`    <Type>${esc(item.typeRaw || item.type)}</Type>`)
    lines.push(`    <Category>${esc(item.category)}</Category>`)
    lines.push(`    <Order>${Number.isFinite(item.order) ? item.order : 100}</Order>`)

    // OS section, only emit supported entries
    lines.push('    <OS>')
    for (const [tag, mapping] of Object.entries(item.os)) {
      lines.push(`      <${tag}>`)
      lines.push(`        <Execute>${mapping.execute ? '1' : '0'}</Execute>`)
      lines.push(`        <Physical>${mapping.physical ? '1' : '0'}</Physical>`)
      lines.push(`        <Virtual>${mapping.virtual ? '1' : '0'}</Virtual>`)
      lines.push(`      </${tag}>`)
    }
    lines.push('    </OS>')

    // Payload
    serializePayload(item.payload, lines)

    lines.push('  </Item>')
  }

  lines.push('</Items>')
  return lines.join('\n')
}

function serializePayload(payload: ItemPayload, lines: string[]): void {
  switch (payload.type) {
    case 'Registry': {
      const r = payload
      lines.push('    <Registry>')
      lines.push(`      <Hive>${esc(r.hive)}</Hive>`)
      lines.push(`      <Name>${esc(r.name)}</Name>`)
      lines.push(`      <Path>${esc(r.path)}</Path>`)
      lines.push(`      <Action>${esc(r.action)}</Action>`)
      lines.push(`      <Value>${esc(r.value)}</Value>`)
      lines.push(`      <Type>${esc(r.registryType)}</Type>`)
      lines.push('    </Registry>')
      break
    }
    case 'Service': {
      lines.push('    <Service>')
      lines.push(`      <Name>${esc(payload.name)}</Name>`)
      lines.push(`      <Action>${esc(payload.action)}</Action>`)
      lines.push('    </Service>')
      break
    }
    case 'ScheduledTask': {
      const st = payload
      lines.push('    <ScheduledTask>')
      lines.push(`      <Name>${esc(st.name)}</Name>`)
      lines.push(`      <Path>${esc(st.path)}</Path>`)
      lines.push(`      <Action>${esc(st.action)}</Action>`)
      lines.push('    </ScheduledTask>')
      break
    }
    case 'StoreApp': {
      lines.push('    <StoreApp>')
      lines.push(`      <Name>${esc(payload.name)}</Name>`)
      lines.push('    </StoreApp>')
      break
    }
    case 'PowerShell': {
      const ps = payload
      const safeScript = ps.script.replace(/]]>/g, ']]>]]><![CDATA[')
      lines.push('    <PowerShell>')
      lines.push(`      <Engine>${esc(ps.engine)}</Engine>`)
      lines.push(`      <Script><![CDATA[${safeScript}]]><\/Script>`)
      lines.push('    </PowerShell>')
      break
    }
    case 'FileFolder': {
      const ff = payload
      lines.push('    <FileFolder>')
      lines.push(`      <Path>${esc(ff.path)}</Path>`)
      lines.push(`      <Action>${esc(ff.action)}</Action>`)
      lines.push(`      <ItemType>${esc(ff.itemType)}</ItemType>`)
      lines.push(`      <NewName>${esc(ff.newName)}</NewName>`)
      lines.push('    </FileFolder>')
      break
    }
    // Unknown: write nothing
  }
}

function esc(str: string): string {
  return (str ?? '').toString().trim()
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}
