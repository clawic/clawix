// Memory mirrors the Mac Memory screen. Wire frames not yet exposed; show
// a placeholder layout matching the Mac chrome.
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
                Codex memory entries are managed on your Mac. Editing from the web requires a memory
                wire frame, which lands in a future schema bump. Until then, use the Memory panel in
                the Mac app to add or revise entries; they will be visible to your sessions here
                automatically.
              </p>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
