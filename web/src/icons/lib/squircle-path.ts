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

// CoreGraphics-style addArc(tangent1End, tangent2End, radius) translated to
// SVG path commands relative to current pen position P0. Returns the SVG
// fragment (line + arc) that goes from a sensible start of the rounded corner
// to its end, assuming the pen was last at p0.
export function arcTangent(
  p0: [number, number],
  t1: [number, number],
  t2: [number, number],
  r: number,
): string {
  const ax = t1[0] - p0[0];
  const ay = t1[1] - p0[1];
  const bx = t2[0] - t1[0];
  const by = t2[1] - t1[1];
  const lenA = Math.hypot(ax, ay);
  const lenB = Math.hypot(bx, by);
  if (lenA < 1e-6 || lenB < 1e-6) return `L${t1[0]},${t1[1]}`;
  const ux = ax / lenA;
  const uy = ay / lenA;
  const vx = bx / lenB;
  const vy = by / lenB;
  const cos = -ux * vx - uy * vy;
  const halfAngle = Math.acos(Math.max(-1, Math.min(1, cos))) / 2;
  const tan = Math.tan(halfAngle);
  if (tan < 1e-6) return `L${t1[0]},${t1[1]}`;
  const d = r / tan;
  const sx = t1[0] - ux * d;
  const sy = t1[1] - uy * d;
  const ex = t1[0] + vx * d;
  const ey = t1[1] + vy * d;
  const cross = ux * vy - uy * vx;
  const sweep = cross < 0 ? 0 : 1;
  return `L${sx.toFixed(3)},${sy.toFixed(3)} A${r},${r} 0 0 ${sweep} ${ex.toFixed(3)},${ey.toFixed(3)}`;
}
