// Modal sheet mirror (SheetChrome.swift). Backdrop blur (.hudWindow,
// .behindWindow), fill rgba(26,26,26,0.78), popup stroke, shadow 22/12/0.40,
// radius 18 (cornerRadius default).
import { ReactNode, useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";

interface Props {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  width?: number;
}

export function Sheet({ open, onClose, children, width = 420 }: Props) {
  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[3000] grid place-items-center"
          style={{ background: "rgba(0,0,0,0.30)" }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.18, ease: [0, 0, 0.2, 1] }}
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) onClose();
          }}
        >
          <motion.div
            role="dialog"
            aria-modal="true"
            className="sheet-backdrop"
            style={{
              width,
              maxWidth: "calc(100vw - 48px)",
              borderRadius: 18,
              boxShadow: "var(--shadow-sheet), inset 0 0 0 0.5px var(--color-popup-stroke)",
              overflow: "hidden",
            }}
            initial={{ opacity: 0, scale: 0.97, y: 8 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.97, y: 8 }}
            transition={{ duration: 0.2, ease: [0, 0, 0.2, 1] }}
          >
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

interface FooterProps {
  children: ReactNode;
}
export function SheetHeader({ title, subtitle }: { title: ReactNode; subtitle?: ReactNode }) {
  return (
    <div className="px-5 pt-5 pb-3">
      <div style={{ fontSize: 17, fontVariationSettings: '"wght" 800', letterSpacing: "-0.02em" }}>
        {title}
      </div>
      {subtitle && (
        <div
          className="mt-1"
          style={{ fontSize: 12.5, color: "var(--color-fg-secondary)", fontVariationSettings: '"wght" 600' }}
        >
          {subtitle}
        </div>
      )}
    </div>
  );
}
export function SheetBody({ children }: { children: ReactNode }) {
  return <div className="px-5 py-3">{children}</div>;
}
export function SheetFooter({ children }: FooterProps) {
  return <div className="px-5 pt-3 pb-5 flex items-center justify-end gap-2">{children}</div>;
}
