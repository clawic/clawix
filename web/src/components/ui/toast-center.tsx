// ToastCenter mirror (ToastCenter.swift). Singleton bus + ToastHost
// renderer mounted once at the app root. spring(420,38) on enter,
// easeIn 220ms on exit. Auto-dismiss default 2.4s.
import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { CircleCheck, CircleAlert, X } from "lucide-react";

export type ToastIcon = "checkCircle" | "info" | "warning" | "error" | "none";

interface ToastItem {
  id: number;
  message: string;
  icon: ToastIcon;
}

let nextId = 1;
let listeners = new Set<(item: ToastItem | null) => void>();
let dismissTimer: number | null = null;
let current: ToastItem | null = null;

function setCurrent(item: ToastItem | null) {
  current = item;
  for (const l of listeners) l(item);
}

export const Toast = {
  show(message: string, icon: ToastIcon = "checkCircle", durationMs = 2400) {
    const item: ToastItem = { id: nextId++, message, icon };
    if (dismissTimer != null) window.clearTimeout(dismissTimer);
    setCurrent(item);
    dismissTimer = window.setTimeout(() => {
      if (current?.id === item.id) setCurrent(null);
    }, durationMs);
  },
  dismiss() {
    if (dismissTimer != null) window.clearTimeout(dismissTimer);
    dismissTimer = null;
    setCurrent(null);
  },
};

function useToast(): ToastItem | null {
  const [item, setItem] = useState<ToastItem | null>(current);
  useEffect(() => {
    listeners.add(setItem);
    return () => {
      listeners.delete(setItem);
    };
  }, []);
  return item;
}

export function ToastHost() {
  const item = useToast();

  return (
    <div
      className="pointer-events-none fixed inset-x-0 top-0 z-[5000] flex justify-center"
      style={{ paddingTop: 16 }}
    >
      <AnimatePresence>
        {item && (
          <motion.div
            key={item.id}
            className="pointer-events-auto inline-flex items-center gap-2.5 toast-backdrop"
            style={{
              borderRadius: 9999,
              boxShadow: "var(--shadow-toast), inset 0 0 0 0.6px rgba(255,255,255,0.10)",
              padding: "8px 8px 8px 14px",
              color: "rgba(255,255,255,0.98)",
            }}
            initial={{ opacity: 0, y: -16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -16 }}
            transition={{ type: "spring", stiffness: 420, damping: 38, mass: 0.85 }}
          >
            <ToastIconView icon={item.icon} />
            <span style={{ fontSize: 13, fontVariationSettings: '"wght" 800' }}>{item.message}</span>
            <button
              onClick={() => Toast.dismiss()}
              className="grid place-items-center hover:text-white"
              style={{ width: 18, height: 18, color: "rgba(255,255,255,0.62)" }}
              aria-label="Dismiss notification"
            >
              <X size={11} strokeWidth={1.5} />
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function ToastIconView({ icon }: { icon: ToastIcon }) {
  switch (icon) {
    case "checkCircle":
      return <CircleCheck size={14} strokeWidth={1.5} color="rgba(255,255,255,0.92)" />;
    case "info":
      return <CircleAlert size={14} strokeWidth={1.5} color="rgba(255,255,255,0.92)" />;
    case "warning":
      return <CircleAlert size={14} strokeWidth={1.5} color="rgb(242,199,102)" />;
    case "error":
      return <CircleAlert size={14} strokeWidth={1.5} color="rgb(242,115,115)" />;
    default:
      return null;
  }
}
