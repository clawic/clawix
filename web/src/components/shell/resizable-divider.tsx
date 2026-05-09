// 10px-wide invisible drag handle straddling a column edge, mirroring
// SidebarResizeHandle from ContentView.swift (5pt inside, 5pt outside).
// Hover shows a subtle white rule.
import { useEffect, useRef, useState } from "react";

interface Props {
  width: number;
  min: number;
  max: number;
  onChange: (next: number) => void;
  side: "left" | "right";
}

export function ResizableDivider({ width, min, max, onChange, side }: Props) {
  const [hovered, setHovered] = useState(false);
  const [dragging, setDragging] = useState(false);
  const startRef = useRef<{ x: number; w: number } | null>(null);

  useEffect(() => {
    if (!dragging) return;
    const onMove = (e: MouseEvent) => {
      if (!startRef.current) return;
      const dx = e.clientX - startRef.current.x;
      const next = side === "left" ? startRef.current.w + dx : startRef.current.w - dx;
      onChange(Math.max(min, Math.min(max, next)));
    };
    const onUp = () => {
      setDragging(false);
      startRef.current = null;
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    return () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
    };
  }, [dragging, min, max, onChange, side]);

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onMouseDown={(e) => {
        startRef.current = { x: e.clientX, w: width };
        setDragging(true);
      }}
      style={{
        width: 10,
        marginLeft: side === "left" ? -5 : 0,
        marginRight: side === "right" ? -5 : 0,
        cursor: "col-resize",
        position: "relative",
        flexShrink: 0,
        zIndex: 10,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: "0 4px",
          background: hovered || dragging ? "rgba(255,255,255,0.06)" : "transparent",
          transition: "background 120ms cubic-bezier(0,0,0.2,1)",
        }}
      />
    </div>
  );
}
