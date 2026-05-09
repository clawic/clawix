// Mirror of SettingsIcon.swift: 6-lobe rosette + outlined hub.
// 28-grid, rT=10.5, rB=8.2, K=0.27, hub r=2.8.
import { useMemo } from "react";
import type { IconProps } from "../lib/types";

function buildPath() {
  const cx = 14;
  const cy = 14;
  const rT = 10.5;
  const rB = 8.2;
  const K = 0.27;
  const n = 12;
  type Node = { p: [number, number]; cOut: [number, number]; cIn: [number, number] };
  const nodes: Node[] = [];
  for (let i = 0; i < n; i++) {
    const theta = (i * 2 * Math.PI) / n;
    const r = i % 2 === 0 ? rT : rB;
    const x = cx + r * Math.sin(theta);
    const y = cy - r * Math.cos(theta);
    const tx = Math.cos(theta);
    const ty = Math.sin(theta);
    const d = K * r;
    nodes.push({
      p: [x, y],
      cOut: [x + d * tx, y + d * ty],
      cIn: [x - d * tx, y - d * ty],
    });
  }
  const first = nodes[0]!;
  let path = `M${first.p[0].toFixed(3)},${first.p[1].toFixed(3)}`;
  for (let i = 0; i < n; i++) {
    const cur = nodes[i]!;
    const nxt = nodes[(i + 1) % n]!;
    path += ` C${cur.cOut[0].toFixed(3)},${cur.cOut[1].toFixed(3)} ${nxt.cIn[0].toFixed(3)},${nxt.cIn[1].toFixed(3)} ${nxt.p[0].toFixed(3)},${nxt.p[1].toFixed(3)}`;
  }
  path += " Z";
  return path;
}

export function SettingsIcon({ size = 14, color = "currentColor", strokeWidth, className, style }: IconProps) {
  const d = useMemo(buildPath, []);
  const lw = strokeWidth ?? 2.5;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 28 28"
      fill="none"
      stroke={color}
      strokeWidth={lw}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      style={style}
    >
      <path d={d} />
      <circle cx="14" cy="14" r="3" />
    </svg>
  );
}
