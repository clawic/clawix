/**
 * MenuPopup mirrors `ModelMenuPopup` from the macOS app. 12pt radius, dark
 * 0.135 alpha bg, 0.10 alpha border, soft shadow, compact 7pt padding,
 * row hover with the `MenuRowHover` background lift.
 */
import { ReactNode, useEffect, useRef } from "react";
import cx from "../lib/cx";

export interface MenuPopupProps {
  open: boolean;
  onClose: () => void;
  anchor?: { x: number; y: number };
  children: ReactNode;
  className?: string;
}

export function MenuPopup({ open, onClose, anchor, children, className }: MenuPopupProps) {
  const ref = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    const onDocClick = (ev: MouseEvent) => {
      if (!ref.current?.contains(ev.target as Node)) onClose();
    };
    const onKey = (ev: KeyboardEvent) => {
      if (ev.key === "Escape") onClose();
    };
    document.addEventListener("mousedown", onDocClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDocClick);
      document.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);

  if (!open) return null;

  const style = anchor ? { left: anchor.x, top: anchor.y } : undefined;
  return (
    <div
      ref={ref}
      className={cx(
        "fixed z-50 min-w-[180px] max-w-[280px] py-[7px] rounded-[12px] border border-[rgba(255,255,255,0.10)] bg-[rgba(20,20,24,0.92)] backdrop-blur-2xl shadow-[var(--shadow-pop)]",
        className,
      )}
      style={style}
      role="menu"
    >
      {children}
    </div>
  );
}

export interface MenuRowProps {
  icon?: ReactNode;
  label: ReactNode;
  hint?: ReactNode;
  onClick?: () => void;
  destructive?: boolean;
  selected?: boolean;
  disabled?: boolean;
}

export function MenuRow({ icon, label, hint, onClick, destructive, selected, disabled }: MenuRowProps) {
  return (
    <button
      role="menuitem"
      onClick={onClick}
      disabled={disabled}
      className={cx(
        "flex items-center gap-2.5 w-full text-left px-3 py-1.5 text-[13px] rounded-[8px] mx-[3px] my-[1px]",
        !disabled && "hover:bg-[rgba(255,255,255,0.07)]",
        selected && "bg-[rgba(255,255,255,0.05)]",
        destructive ? "text-[var(--color-danger)]" : "text-[var(--color-fg)]",
        disabled && "opacity-40",
      )}
      style={{ width: "calc(100% - 6px)" }}
    >
      {icon && <span className="w-4 h-4 grid place-items-center opacity-80">{icon}</span>}
      <span className="flex-1 truncate">{label}</span>
      {hint && <span className="text-[11px] text-[var(--color-fg-dim)]">{hint}</span>}
    </button>
  );
}

export function MenuDivider() {
  return <div className="my-[5px] mx-[10px] h-px bg-[rgba(255,255,255,0.07)]" />;
}
