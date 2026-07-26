let el: HTMLDivElement | null = null

function getEl(): HTMLDivElement {
  if (!el) {
    el = document.createElement('div')
    el.className = 'app-tooltip'
    document.body.appendChild(el)
  }
  return el
}

function show(target: HTMLElement) {
  const text = target.getAttribute('data-tooltip')
  if (!text) return

  const tip = getEl()
  tip.textContent = text
  tip.style.display = 'block'
  tip.style.opacity = '0'

  // Force layout so we can measure the tooltip's rendered size
  void tip.offsetHeight

  const tr = target.getBoundingClientRect()
  const tw = tip.offsetWidth
  const th = tip.offsetHeight
  const gap = 7

  // Vertical: prefer below, fall back to above
  const spaceBelow = window.innerHeight - tr.bottom - gap
  const spaceAbove = tr.top - gap
  const top = spaceBelow >= th || spaceBelow >= spaceAbove
    ? tr.bottom + gap
    : tr.top - th - gap

  // Horizontal: center on target, clamp within viewport
  const left = Math.max(8, Math.min(
    tr.left + tr.width / 2 - tw / 2,
    window.innerWidth - tw - 8
  ))

  tip.style.top = top + 'px'
  tip.style.left = left + 'px'
  tip.style.opacity = '1'
}

function hide() {
  if (el) el.style.display = 'none'
}

/**
 * Dismiss the tooltip from code. Needed when a click opens something over the
 * hovered element, so the pointer never leaves, so no mouseout fires.
 */
export function hideTooltip() {
  hide()
}

export function initTooltips() {
  document.addEventListener('mouseover', e => {
    const target = (e.target as HTMLElement).closest('[data-tooltip]') as HTMLElement | null
    if (target) show(target)
    else hide()
  })
  document.addEventListener('mouseout', e => {
    const related = e.relatedTarget as HTMLElement | null
    if (!related?.closest('[data-tooltip]')) hide()
  })
  document.addEventListener('scroll', hide, true)
}
