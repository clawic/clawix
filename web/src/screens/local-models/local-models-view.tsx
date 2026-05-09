// LocalModels mirror.
import { PageHeader, Card } from "../../components/ui";

export function LocalModelsView() {
  return (
    <div className="h-full flex flex-col">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title="Local models" subtitle="Ollama runtime exposed via the bridge." />
          <Card>
            <div className="space-y-2" style={{ padding: 16 }}>
              <div
                style={{ fontSize: 14, fontVariationSettings: '"wght" 800', letterSpacing: "-0.01em" }}
              >
                Ollama on your Mac
              </div>
              <p
                style={{
                  fontSize: 12.5,
                  color: "var(--color-fg-secondary)",
                  lineHeight: 1.55,
                }}
              >
                Install, start and manage Ollama from the Mac app. Once a model is running, sessions
                opened from the web will route through it transparently via the same bridge.
              </p>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
