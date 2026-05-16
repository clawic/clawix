// Content panel with continuous-corner squircle on the leading edges
// (top-left + bottom-left). The trailing edges round only when the right
// sidebar is open, mirroring ContentView.swift:61-69.
//
// Radius 14 is small enough that a CSS border-radius is visually close to
// Apple's continuous corner; for any region where the difference is
// visible we'd use a custom clip-path. Uneven per-corner radii keep this
// shell on native CSS here.
import type { ReactNode } from "react";

interface Props {
  rightSidebarOpen: boolean;
  children: ReactNode;
}

export function ContentShell({ rightSidebarOpen, children }: Props) {
  const radius = 14;
  const trailing = rightSidebarOpen ? `${radius}px` : "0px";
  return (
    <div
      className="h-full flex-1 min-w-0 overflow-hidden"
      style={{
        background: "var(--color-bg)",
        borderRadius: `${radius}px ${trailing} ${trailing} ${radius}px`,
      }}
    >
      {children}
    </div>
  );
}
