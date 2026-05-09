/**
 * Database mirror. Like Memory, the dedicated database wire frames are
 * not yet exposed by the bridge schema. The screen renders the layout
 * with a "Coming soon" banner so the IA route map stays complete.
 */
import { DatabaseIcon } from "../../icons";

export function DatabaseView() {
  return (
    <div className="h-full flex flex-col">
      <header className="h-[56px] px-6 flex items-center gap-3 border-b border-[var(--color-border)]">
        <DatabaseIcon size={16} className="text-[var(--color-fg-muted)]" />
        <h1 className="text-[15px] font-medium tracking-[-0.01em]">Database</h1>
      </header>
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto py-10 px-6">
          <div className="rounded-[16px] border border-[var(--color-border)] bg-[var(--color-bg-elev-1)] p-6 space-y-3">
            <div className="text-[14px] font-medium tracking-[-0.01em]">Managed datasets</div>
            <p className="text-[12.5px] text-[var(--color-fg-muted)] leading-relaxed">
              Database collections, records and bulk operations are exposed on the Mac. Web access
              requires a database wire frame, scheduled for a follow-up schema bump. The Mac panel
              stays canonical until then.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
