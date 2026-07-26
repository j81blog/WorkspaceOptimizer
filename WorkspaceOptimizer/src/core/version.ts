/**
 * Template version stamping.
 *
 * The format is `yyyy.Mdd.Hmm`, matching the build stamps already used in
 * `public/Windows.xml` (e.g. 2026.429.2230 = 29 April 2026, 22:30). Nothing is
 * zero-padded, so no component ever carries a leading zero. A midnight build does
 * stamp as a bare `.0`, which is the honest value rather than a padded one.
 *
 * These are build stamps, not parseable dates. Two deliberate limitations:
 *
 *   - The middle part is ambiguous. `115` is 15 January, but 5 November is `1105`
 *     are distinct values, yet you cannot tell from `115` alone where the month ends.
 *     Padding the month would fix it, at the cost of a leading zero for Jan–Sep.
 *   - They do not sort as plain strings (`.5` sorts after `.2359`). Compare the
 *     parts numerically if ordering ever matters.
 */

/** Build stamp for a given moment, as `yyyy.Mdd.Hmm`. */
export function formatVersion(d: Date): string {
  const month = d.getMonth() + 1                       // 1-12, unpadded
  const day = String(d.getDate()).padStart(2, '0')     // always 2 digits
  const time = d.getHours() * 100 + d.getMinutes()     // 0-2359, never padded
  return `${d.getFullYear()}.${month}${day}.${time}`
}
