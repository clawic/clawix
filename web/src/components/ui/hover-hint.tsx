// HoverHint mirror (HoverHint.swift). Capsule, radius 7, fill #2e2e2e
// (white 0.18), stroke white 22% 0.6px, shadow soft, 1.5s appear delay,
// directional soft nudge in/out.
import { CSSProperties, ReactNode, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";

type Placement = "above" | "below" | "leading" | "trailing";

interface Props {
  label: string;
  placement?: Placement;
  delayMs?: number;
  children: ReactNode;
}

export function HoverHint({ label, placement = "above", delayMs = 1500, children }: Props) {
  const [visible, setVisible] = useState(false);
  const timer = useRef<number | null>(null);

  useEffect(() => () => {
    if (timer.current != null) window.clearTimeout(timer.current);
  }, []);

  function onEnter() {
    if (timer.current != null) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setVisible(true), delayMs);
  }
  function onLeave() {
    if (timer.current != null) window.clearTimeout(timer.current);
    timer.current = null;
    setVisible(false);
  }

  const overlayStyle: CSSProperties = (() => {
    switch (placement) {
      case "above":   return { left: "50%", bottom: "100%", marginBottom: 10, transform: "translateX(-50%)" };
      case "below":   return { left: "50%", top: "100%", marginTop: 10, transform: "translateX(-50%)" };
      case "leading": return { right: "100%", top: "50%", marginRight: 10, transform: "translateY(-50%)" };
      case "trailing":return { left: "100%", top: "50%", marginLeft: 10, transform: "translateY(-50%)" };
    }
  })();

  const nudge: { x: number; y: number } = (() => {
    switch (placement) {
      case "above":   return { x: 0, y: 4 };
      case "below":   return { x: 0, y: -4 };
      case "leading": return { x: 4, y: 0 };
      case "trailing":return { x: -4, y: 0 };
    }
  })();

  return (
    <span
      className="relative inline-flex"
      onMouseEnter={onEnter}
      onMouseLeave={onLeave}
      onFocus={onEnter}
      onBlur={onLeave}
    >
      {children}
      <AnimatePresence>
        {visible && (
          <motion.span
            role="tooltip"
            className="absolute pointer-events-none whitespace-nowrap"
            style={{
              ...overlayStyle,
              zIndex: 999,
              padding: "5px 10px",
              borderRadius: 7,
              background: "var(--color-hint-fill)",
              boxShadow: "var(--shadow-hint), inset 0 0 0 0.6px var(--color-hint-stroke)",
              color: "rgba(255,255,255,0.98)",
              fontSize: 11,
              fontVariationSettings: '"wght" 600',
            }}
            initial={{ opacity: 0, x: nudge.x, y: nudge.y }}
            animate={{ opacity: 1, x: 0, y: 0 }}
            exit={{ opacity: 0, x: nudge.x, y: nudge.y }}
            transition={{ duration: 0.18, ease: [0, 0, 0.2, 1] }}
          >
            {label}
          </motion.span>
        )}
      </AnimatePresence>
    </span>
  );
}
