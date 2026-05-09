// Projects mirrors ProjectPickerView. Lists projects derived from chat
// history + manual additions.
import { useEffect } from "react";
import { useBridgeStore } from "../../bridge/store";
import { FolderOpenIcon } from "../../icons";
import { PageHeader, Card, CardDivider } from "../../components/ui";

export function ProjectsView() {
  const projects = useBridgeStore((s) => s.projects);
  const refresh = useBridgeStore((s) => s.listProjects);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return (
    <div className="h-full flex flex-col">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title="Projects" subtitle="The working directories your chats touched." />
          {projects.length === 0 ? (
            <div
              className="py-6"
              style={{ fontSize: 12.5, color: "var(--color-fg-secondary)" }}
            >
              No projects yet. Start a chat with a working directory to see it here.
            </div>
          ) : (
            <Card>
              {projects.map((p, i) => (
                <div key={p.id}>
                  {i > 0 && <CardDivider />}
                  <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
                    <FolderOpenIcon size={14} color="var(--color-fg-secondary)" />
                    <div className="flex-1 min-w-0">
                      <div
                        className="truncate"
                        style={{ fontSize: 13, fontVariationSettings: '"wght" 700' }}
                      >
                        {p.title}
                      </div>
                      <div
                        className="font-mono truncate"
                        style={{ fontSize: 11.5, color: "var(--color-fg-secondary)" }}
                      >
                        {p.cwd}
                      </div>
                    </div>
                    {p.branch && (
                      <span
                        className="font-mono"
                        style={{ fontSize: 11, color: "var(--color-fg-secondary)" }}
                      >
                        {p.branch}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
