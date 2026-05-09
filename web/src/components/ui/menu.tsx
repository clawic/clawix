// Dropdown / popover menu chrome. Mirrors MenuStyle from ContentView.swift
// (radius 12, fill rgba(34,34,34,0.82) over backdrop blur, popup stroke,
// shadow 18/10/0.40, row padding 9x6, hover pill radius 8 inset 4
// intensity 0.06, easeOut 200ms open).
import { CSSProperties, ReactNode, useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import cx from "../../lib/cx";

interface MenuProps {
  open: boolean;
  onClose: () => void;
  anchorRef: React.RefObject<HTMLElement | null>;
  align?: "start" | "end";
  children: ReactNode;
  minWidth?: number;
}

export function Menu({ open, onClose, anchorRef, align = "start", minWidth = 180, children }: MenuProps) {
  const ref = useRef<HTMLDivElement | null>(null);
  const [pos, setPos] = useState<{ left: number; top: number } | null>(null);

  useEffect(() => {
    if (!open) return;
    const a = anchorRef.current;
    if (!a) return;
    const rect = a.getBoundingClientRect();
    const left = align === "end" ? rect.right - minWidth : rect.left;
    setPos({ left, top: rect.bottom + 6 });
  }, [open, anchorRef, align, minWidth]);

  useEffect(() => {
    if (!open) return;
    function onDoc(e: MouseEvent) {
      if (!ref.current) return;
      if (ref.current.contains(e.target as Node)) return;
      if (anchorRef.current && anchorRef.current.contains(e.target as Node)) return;
      onClose();
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("mousedown", onDoc);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDoc);
      document.removeEventListener("keydown", onKey);
    };
  }, [open, anchorRef, onClose]);

  return (
    <AnimatePresence>
      {open && pos && (
        <motion.div
          ref={ref}
          role="menu"
          className="fixed z-[2000] menu-backdrop"
          style={{
            left: pos.left,
            top: pos.top,
            minWidth,
            borderRadius: 12,
            boxShadow: "var(--shadow-menu), inset 0 0 0 0.5px var(--color-popup-stroke)",
            padding: "4px 0",
          }}
          initial={{ opacity: 0, y: -4, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -4, scale: 0.98 }}
          transition={{ duration: 0.2, ease: [0, 0, 0.2, 1] }}
        >
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  );
}

interface MenuItemProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  icon?: ReactNode;
  trailing?: ReactNode;
  destructive?: boolean;
  children: ReactNode;
}

export function MenuItem({ icon, trailing, destructive, className, children, style, ...rest }: MenuItemProps) {
  const [hovered, setHovered] = useState(false);
  const fontStyle: CSSProperties = {
    fontSize: 13,
    fontVariationSettings: '"wght" 600',
  };
  return (
    <button
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      role="menuitem"
      className={cx(
        "w-full flex items-center gap-1.5 transition-[background-color] duration-[150ms] ease-[var(--ease-row)]",
        className,
      )}
      style={{
        margin: "0 4px",
        width: "calc(100% - 8px)",
        padding: "6px 9px",
        borderRadius: 8,
        background: hovered ? "rgba(255,255,255,0.06)" : "transparent",
        color: destructive ? "var(--color-destructive)" : "var(--color-menu-row-text)",
        ...fontStyle,
        ...style,
      }}
      {...rest}
    >
      {icon && (
        <span
          style={{
            width: 16,
            display: "inline-flex",
            justifyContent: "center",
            color: destructive ? "var(--color-destructive)" : "var(--color-menu-row-icon)",
          }}
        >
          {icon}
        </span>
      )}
      <span className="flex-1 text-left truncate">{children}</span>
      {trailing && (
        <span
          style={{
            color: "var(--color-menu-row-subtle)",
            fontSize: 11,
            fontVariationSettings: '"wght" 600',
          }}
        >
          {trailing}
        </span>
      )}
    </button>
  );
}

export function MenuDivider() {
  return <div style={{ height: 1, margin: "4px 0", background: "var(--color-menu-divider)" }} />;
}

export function MenuHeader({ children }: { children: ReactNode }) {
  return (
    <div
      style={{
        padding: "8px 13px 4px",
        fontSize: 11,
        color: "var(--color-menu-header)",
        fontVariationSettings: '"wght" 700',
        letterSpacing: "-0.01em",
      }}
    >
      {children}
    </div>
  );
}
