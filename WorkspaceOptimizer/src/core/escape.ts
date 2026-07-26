/**
 * Cooperative Escape handling for stacked dialogs.
 *
 * Dialogs listen on `document`, so a nested dialog cannot stop the event reaching an
 * outer one. By the time the outer handler runs, `stopPropagation` is useless and the
 * inner dialog's own state has already changed. Instead the first handler to act marks
 * the event, and every other handler skips it, so one Escape closes exactly one dialog.
 *
 * The mark lives on the event object rather than in a module-level WeakSet, so it works
 * even if two copies of this module exist, which happens whenever something reloads
 * the module graph, as vi.resetModules() does in tests. A set held here would give each
 * copy its own state and silently break the coordination.
 */
const MARK = '__woEscapeHandled'

export function isEscapeHandled(e: Event): boolean {
  return (e as unknown as Record<string, unknown>)[MARK] === true
}

export function markEscapeHandled(e: Event): void {
  try {
    Object.defineProperty(e, MARK, { value: true, configurable: true })
  } catch {
    // Frozen or otherwise unwritable event: worst case both dialogs close, which is
    // the old behaviour rather than a crash.
  }
}

/**
 * Stack of open dialogs, outermost first. `document` listeners fire in registration
 * order, so the claim alone is not enough. An outer dialog registered earlier would
 * claim the event before the nested one ever sees it. Each dialog checks that it is
 * on top before acting.
 */
const stack: symbol[] = []

export function pushDialog(id: symbol): void {
  if (!stack.includes(id)) stack.push(id)
}

export function popDialog(id: symbol): void {
  const i = stack.indexOf(id)
  if (i !== -1) stack.splice(i, 1)
}

/** True when `id` is the most recently opened dialog still open. */
export function isTopDialog(id: symbol): boolean {
  return stack.length > 0 && stack[stack.length - 1] === id
}
