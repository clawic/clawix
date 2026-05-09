/**
 * SlidingSegmented mirrors `SlidingSegmented<T>` from the macOS app. The
 * indicator pill animates to the selected option with a snappy spring.
 *
 * Visual contract:
 *  - Outer container 13pt rounded squircle with subtle inner padding (10pt)
 *  - Indicator inset 4pt inside the container, rounded with same smoothing
 *  - Snappy 320ms transition; non-bouncy curve
 *  - Unselected labels at 60% alpha, selected at full
 */
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
        "relative inline-flex items-center rounded-[13px] bg-[var(--color-bg-elev-1)] border border-[var(--color-border)] p-[3px]",
        size === "sm" ? "h-8 text-[12px]" : "h-10 text-[13px]",
        className,
      )}
    >
      {rect && (
        <motion.div
          aria-hidden
          className="absolute inset-y-[3px] rounded-[10px] bg-[var(--color-bg-elev-3)] shadow-[0_1px_0_rgba(255,255,255,0.06)_inset,0_2px_8px_rgba(0,0,0,0.18)]"
          initial={false}
          animate={{ x: rect.x, width: rect.w }}
          transition={{ type: "spring", stiffness: 500, damping: 40, mass: 0.8 }}
        />
      )}
      {options.map((opt) => (
        <button
          key={opt.value}
          role="tab"
          aria-selected={opt.value === value}
          onClick={() => onChange(opt.value)}
          className={cx(
            "relative z-[1] flex items-center justify-center gap-1.5 px-3.5 rounded-[10px] transition-opacity",
            size === "sm" ? "h-[26px]" : "h-[34px]",
            opt.value === value ? "opacity-100" : "opacity-60 hover:opacity-90",
          )}
        >
          {opt.icon}
          {opt.label}
        </button>
      ))}
    </div>
  );
}
