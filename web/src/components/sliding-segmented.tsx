// SlidingSegmented mirrors `SlidingSegmented<T>` from the macOS app. The
// indicator pill animates to the selected option with the Mac's easeOut
// curve (200ms) instead of a spring. Container chrome aligns with the
// Settings dropdown chrome.
import { useLayoutEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import cx from "../lib/cx";

export interface SegmentedOption<T extends string> {
  value: T;
  label: string;
  icon?: React.ReactNode;
}

export interface SlidingSegmentedProps<T extends string> {
  options: SegmentedOption<T>[];
  value: T;
  onChange: (value: T) => void;
  className?: string;
  size?: "sm" | "md";
}

export function SlidingSegmented<T extends string>({
  options,
  value,
  onChange,
  className,
  size = "md",
}: SlidingSegmentedProps<T>) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [rect, setRect] = useState<{ x: number; w: number } | null>(null);

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const idx = options.findIndex((o) => o.value === value);
    const target = container.children.item(idx) as HTMLElement | null;
    if (!target) return;
    const cR = container.getBoundingClientRect();
    const tR = target.getBoundingClientRect();
    setRect({ x: tR.left - cR.left, w: tR.width });
  }, [value, options]);

  return (
    <div
      ref={containerRef}
      role="tablist"
      className={cx(
        "relative inline-flex items-center",
        size === "sm" ? "h-7 text-[11.5px]" : "h-9 text-[12.5px]",
        className,
      )}
      style={{
        background: "rgba(255,255,255,0.04)",
        boxShadow: "inset 0 0 0 0.5px var(--color-popup-stroke)",
        borderRadius: 12,
        padding: 3,
        fontVariationSettings: '"wght" 700',
      }}
    >
      {rect && (
        <motion.div
          aria-hidden
          className="absolute"
          style={{
            top: 3,
            bottom: 3,
            background: "rgba(255,255,255,0.10)",
            borderRadius: 9,
            boxShadow:
              "inset 0 0 0 0.5px rgba(255,255,255,0.08), 0 1px 2px rgba(0,0,0,0.18)",
          }}
          initial={false}
          animate={{ x: rect.x, width: rect.w }}
          transition={{ duration: 0.2, ease: [0, 0, 0.2, 1] }}
        />
      )}
      {options.map((opt) => (
        <button
          key={opt.value}
          role="tab"
          aria-selected={opt.value === value}
          onClick={() => onChange(opt.value)}
          className={cx(
            "relative z-[1] flex items-center justify-center gap-1.5 transition-opacity",
            size === "sm" ? "h-[22px] px-3" : "h-[30px] px-3.5",
            opt.value === value ? "opacity-100" : "opacity-60 hover:opacity-90",
          )}
          style={{ borderRadius: 9 }}
        >
          {opt.icon}
          {opt.label}
        </button>
      ))}
    </div>
  );
}
