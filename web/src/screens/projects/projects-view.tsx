/**
 * Projects mirrors the macOS ProjectPickerView. Lists the projects the
 * daemon derived from chat history + manual additions.
 */
import { useEffect } from "react";
import { useBridgeStore } from "../../bridge/store";
import { FolderOpenIcon } from "../../icons";

export function ProjectsView() {
  const projects = useBridgeStore((s) => s.projects);
  const refresh = useBridgeStore((s) => s.listProjects);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return (
    <div className="h-full flex flex-col">
      <header className="h-[56px] px-6 flex items-center gap-3 border-b border-[var(--color-border)]">
        <FolderOpenIcon size={16} className="text-[var(--color-fg-muted)]" />
        <h1 className="text-[15px] font-medium tracking-[-0.01em]">Projects</h1>
      </header>
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto py-8 px-6">
          {projects.length === 0 ? (
            <div className="text-[12.5px] text-[var(--color-fg-muted)] py-6">
              No projects yet. Start a chat with a working directory to see it here.
            </div>
          ) : (
            <ul className="space-y-2">
              {projects.map((p) => (
                <li
                  key={p.id}
                  className="flex items-center gap-3 px-3 py-3 rounded-[14px] bg-[var(--color-bg-elev-1)] border border-[var(--color-border)]"
                >
                  <FolderOpenIcon size={14} className="text-[var(--color-fg-muted)]" />
                  <div className="flex-1 min-w-0">
                    <div className="text-[13.5px] truncate">{p.title}</div>
                    <div className="font-mono text-[11.5px] text-[var(--color-fg-muted)] truncate">{p.cwd}</div>
                  </div>
                  {p.branch && (
                    <span className="text-[11px] text-[var(--color-fg-muted)] font-mono">{p.branch}</span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}
