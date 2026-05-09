// Database mirror. Wire frames not yet exposed; show placeholder layout
// matching the Mac chrome.
import { PageHeader, Card } from "../../components/ui";

export function DatabaseView() {
  return (
    <div className="h-full flex flex-col">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title="Database" subtitle="Managed datasets exposed by the daemon." />
          <Card>
            <div className="space-y-2" style={{ padding: 16 }}>
              <div
                style={{ fontSize: 14, fontVariationSettings: '"wght" 800', letterSpacing: "-0.01em" }}
              >
                Managed datasets
              </div>
              <p
                style={{
                  fontSize: 12.5,
                  color: "var(--color-fg-secondary)",
                  lineHeight: 1.55,
                }}
              >
                Database collections, records and bulk operations are exposed on the Mac. Web access
                requires a database wire frame, scheduled for a follow-up schema bump. The Mac panel
                stays canonical until then.
              </p>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
