// Database companion surface. Mac + ClawJS own v1 record editing; the
// web view states that boundary instead of pretending to be an unwired editor.
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
                Database collections, records and bulk operations are v1 surfaces on the Mac and
                through ClawJS CLI/API. This web companion keeps the boundary visible while record
                mutation stays with those canonical surfaces.
              </p>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
