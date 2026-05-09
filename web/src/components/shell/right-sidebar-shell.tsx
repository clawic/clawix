// Right sidebar shell. Mirror of the Mac right-sidebar column.
// Visible only when open; uses the global sidebar backdrop (no own bg).
import type { ReactNode } from "react";

interface Props {
  width: number;
  open: boolean;
  children: ReactNode;
}

export function RightSidebarShell({ width, open, children }: Props) {
  if (!open) return null;
  return (
    <div
      style={{ width, flexShrink: 0 }}
      className="h-full flex flex-col overflow-hidden"
    >
      {children}
    </div>
  );
}
