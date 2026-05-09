// Left sidebar container. Replicates the Mac shell:
// the sidebar's background is the global blur (ignoresSafeArea on Mac),
// not its own painted column. Children are mounted directly without an
// extra panel chrome.
import type { ReactNode } from "react";

interface Props {
  width: number;
  children: ReactNode;
}

export function SidebarShell({ width, children }: Props) {
  return (
    <div
      style={{ width, flexShrink: 0 }}
      className="h-full flex flex-col overflow-hidden"
    >
      {children}
    </div>
  );
}
