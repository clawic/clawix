/** Tiny className composer — avoids pulling in `clsx` as a dep. */
export default function cx(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(" ");
}
