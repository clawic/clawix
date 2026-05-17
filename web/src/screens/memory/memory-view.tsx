// Memory companion surface. Mac + ClawJS own v1 memory edits; the web view
// states that boundary while sessions consume the shared context.
import { PageHeader, Card } from "../../components/ui";

export function MemoryView() {
  return (
    <div className="h-full flex flex-col">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title="Memory" subtitle="Persistent context Codex can recall across chats." />
          <Card>
            <div className="space-y-2" style={{ padding: "16px" }}>
              <div
                style={{ fontSize: 14, fontVariationSettings: '"wght" 800', letterSpacing: "-0.01em" }}
              >
                Persistent memory
              </div>
              <p
                style={{
                  fontSize: 12.5,
                  color: "var(--color-fg-secondary)",
                  lineHeight: 1.55,
                }}
              >
                Codex memory entries are managed through the Mac UI and ClawJS framework APIs.
                Sessions here consume that shared context automatically while edits remain on the
                canonical v1 surfaces.
              </p>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
