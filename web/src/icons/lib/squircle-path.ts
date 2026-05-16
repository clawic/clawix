// Superellipse path generator. n=5 matches Apple's iOS app-icon mask shape.
// Used by StopSquircle and any future glyph that needs the same curvature.
export function superellipsePath(width: number, height: number, n = 5, segments = 96): string {
  const cx = width / 2;
  const cy = height / 2;
  const a = width / 2;
  const b = height / 2;
  const parts: string[] = [];
  for (let i = 0; i <= segments; i++) {
    const t = (i / segments) * 2 * Math.PI;
    const cosT = Math.cos(t);
    const sinT = Math.sin(t);
    const x = cx + (cosT === 0 ? 0 : Math.sign(cosT) * Math.pow(Math.abs(cosT), 2 / n) * a);
    const y = cy + (sinT === 0 ? 0 : Math.sign(sinT) * Math.pow(Math.abs(sinT), 2 / n) * b);
    parts.push(`${i === 0 ? "M" : "L"}${x.toFixed(3)},${y.toFixed(3)}`);
  }
  return parts.join(" ") + " Z";
}
