// MCP mirror.
import { PageHeader, Card } from "../../components/ui";

export function McpView() {
  return (
    <div className="h-full flex flex-col">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title="MCP servers" subtitle="Model Context Protocol endpoints." />
          <Card>
            <div className="space-y-2" style={{ padding: 16 }}>
              <div
                style={{ fontSize: 14, fontVariationSettings: '"wght" 800', letterSpacing: "-0.01em" }}
              >
                Connected MCP servers
              </div>
              <p
                style={{
                  fontSize: 12.5,
                  color: "var(--color-fg-secondary)",
                  lineHeight: 1.55,
                }}
              >
                MCP server configuration is owned by the Mac app. Web edits require a dedicated MCP
                wire frame; until then, manage servers from the Mac and the bridge will surface their
                tools to your sessions automatically.
              </p>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
