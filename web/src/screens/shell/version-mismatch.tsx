/**
 * Banner shown when the daemon advertises a higher protocolVersion than
 * this SPA knows about. The fix is to update the Mac app, which will ship
 * a newer web bundle inside its daemon.
 */
export function VersionMismatchBanner({ serverVersion }: { serverVersion: number }) {
  return (
    <div className="px-5 py-3 border-b border-[var(--color-banner-danger-fg)]/40 bg-[var(--color-banner-danger-fg)]/10 text-[12.5px] text-[var(--color-banner-danger-fg)] flex items-center justify-between">
      <div>
        Your Mac is running a newer Clawix bridge (protocol v{serverVersion}). Update the web client
        by reloading this page after the Mac app finishes launching the new daemon.
      </div>
      <button
        onClick={() => window.location.reload()}
        className="h-8 px-3 rounded-[8px] bg-[var(--color-banner-danger-fg)]/20 hover:bg-[var(--color-banner-danger-fg)]/30 text-[12px]"
      >
        Reload
      </button>
    </div>
  );
}
