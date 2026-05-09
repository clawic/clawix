/**
 * LocalModels mirror. Same constraint as Memory/Database/MCP: layout-ready,
 * waiting for dedicated wire frames.
 */
import { ServerIcon } from "../../icons";

export function LocalModelsView() {
  return (
    <div className="h-full flex flex-col">
      <header className="h-[56px] px-6 flex items-center gap-3 border-b border-[var(--color-border)]">
        <ServerIcon size={16} className="text-[var(--color-fg-muted)]" />
        <h1 className="text-[15px] font-medium tracking-[-0.01em]">Local models</h1>
      </header>
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto py-10 px-6">
          <div className="rounded-[16px] border border-[var(--color-border)] bg-[var(--color-bg-elev-1)] p-6 space-y-3">
            <div className="text-[14px] font-medium tracking-[-0.01em]">Ollama on your Mac</div>
            <p className="text-[12.5px] text-[var(--color-fg-muted)] leading-relaxed">
              Install, start and manage Ollama from the Mac app. Once a model is running, sessions
              opened from the web will route through it transparently via the same bridge.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
