/**
 * Settings mirrors the macOS Settings panel. Sections that are macOS-only
 * (dictation hotkey, menu bar, login items) appear as a "Manage on Mac"
 * affordance instead of being silently dropped.
 */
import { useState } from "react";
import { useBridgeStore } from "../../bridge/store";
import { SlidingSegmented } from "../../components/sliding-segmented";
import { storage, StorageKeys } from "../../lib/storage";
import cx from "../../lib/cx";

type Tab = "general" | "appearance" | "advanced";

export function SettingsView() {
  const [tab, setTab] = useState<Tab>("general");
  return (
    <div className="h-full flex flex-col">
      <header className="h-[56px] px-6 flex items-center gap-4 border-b border-[var(--color-border)]">
        <h1 className="text-[15px] font-medium tracking-[-0.01em]">Settings</h1>
        <SlidingSegmented<Tab>
          size="sm"
          options={[
            { value: "general", label: "General" },
            { value: "appearance", label: "Appearance" },
            { value: "advanced", label: "Advanced" },
          ]}
          value={tab}
          onChange={setTab}
        />
      </header>
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[720px] mx-auto py-8 px-6 space-y-6">
          {tab === "general" && <GeneralSettings />}
          {tab === "appearance" && <AppearanceSettings />}
          {tab === "advanced" && <AdvancedSettings />}
        </div>
      </div>
    </div>
  );
}

function Section({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-[16px] border border-[var(--color-border)] bg-[var(--color-bg-elev-1)] p-5 space-y-4">
      <div>
        <div className="text-[14px] font-medium tracking-[-0.01em]">{title}</div>
        {description && <div className="text-[12px] text-[var(--color-fg-muted)] mt-1">{description}</div>}
      </div>
      {children}
    </section>
  );
}

function Row({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-6 py-2 border-t first:border-t-0 border-[var(--color-border)]">
      <div className="min-w-0">
        <div className="text-[13px]">{label}</div>
        {hint && <div className="text-[11.5px] text-[var(--color-fg-muted)] mt-0.5">{hint}</div>}
      </div>
      {children}
    </div>
  );
}

function GeneralSettings() {
  const macName = useBridgeStore((s) => s.macName);
  const detach = useBridgeStore((s) => s.detach);
  const [deviceName, setDeviceName] = useState(() => storage.get<string>(StorageKeys.deviceName) ?? "");

  return (
    <>
      <Section title="Connection" description="Bridge identity for this browser session.">
        <Row label="Paired with" hint={macName ? `Currently bonded to ${macName}` : "Not paired"}>
          <code className="text-[12px] text-[var(--color-fg-muted)]">{macName ?? "—"}</code>
        </Row>
        <Row label="Device label" hint="Shown in the Mac app's connected peers list.">
          <input
            value={deviceName}
            onChange={(e) => {
              setDeviceName(e.target.value);
              storage.set(StorageKeys.deviceName, e.target.value);
            }}
            placeholder="Web"
            className="h-9 w-[220px] px-3 rounded-[10px] bg-[var(--color-bg-elev-2)] border border-[var(--color-border)] outline-none focus:border-[var(--color-border-strong)] text-[13px]"
          />
        </Row>
        <Row label="Unpair this browser" hint="Clears the local token. You will need to enter the short code again.">
          <button
            onClick={() => {
              storage.remove(StorageKeys.bearer);
              detach();
              window.location.reload();
            }}
            className="h-9 px-3 rounded-[10px] border border-[var(--color-border)] hover:bg-[var(--color-bg-elev-2)] text-[12px] text-[var(--color-danger)]"
          >
            Unpair
          </button>
        </Row>
      </Section>

      <Section title="Mac-only" description="These features live on your Mac. Use the Mac app to change them.">
        <Row label="Global dictation hotkey">
          <span className="text-[12px] text-[var(--color-fg-muted)]">Manage on Mac</span>
        </Row>
        <Row label="Menu bar item">
          <span className="text-[12px] text-[var(--color-fg-muted)]">Manage on Mac</span>
        </Row>
        <Row label="Open at login">
          <span className="text-[12px] text-[var(--color-fg-muted)]">Manage on Mac</span>
        </Row>
      </Section>
    </>
  );
}

function AppearanceSettings() {
  const [scheme, setScheme] = useState<"system" | "dark" | "light">("system");
  return (
    <Section title="Appearance">
      <Row label="Color scheme">
        <SlidingSegmented
          size="sm"
          options={[
            { value: "system", label: "System" },
            { value: "dark", label: "Dark" },
            { value: "light", label: "Light" },
          ]}
          value={scheme}
          onChange={setScheme}
        />
      </Row>
    </Section>
  );
}

function AdvancedSettings() {
  const bridge = useBridgeStore((s) => s.bridge);
  const conn = useBridgeStore((s) => s.connection);
  const rl = useBridgeStore((s) => s.rateLimits);

  return (
    <>
      <Section title="Bridge runtime">
        <Row label="Daemon state">
          <code className="text-[12px] text-[var(--color-fg-muted)]">{bridge.state}</code>
        </Row>
        <Row label="Chat count">
          <code className="text-[12px] text-[var(--color-fg-muted)]">{bridge.chatCount}</code>
        </Row>
        <Row label="Connection">
          <code className="text-[12px] text-[var(--color-fg-muted)]">{conn.kind}</code>
        </Row>
      </Section>
      <Section title="Rate limits" description="Pulled from your Mac. Reflects the current Codex account state.">
        {!rl ? (
          <div className="text-[12px] text-[var(--color-fg-muted)]">No data yet.</div>
        ) : (
          <div className="space-y-2">
            {rl.primary && (
              <Row label="Primary window">
                <code className="text-[12px]">{rl.primary.usedPercent}% used</code>
              </Row>
            )}
            {rl.secondary && (
              <Row label="Secondary window">
                <code className="text-[12px]">{rl.secondary.usedPercent}% used</code>
              </Row>
            )}
            {rl.credits && (
              <Row label="Credits">
                <code className={cx("text-[12px]", rl.credits.unlimited && "text-[var(--color-success)]")}>
                  {rl.credits.unlimited ? "Unlimited" : (rl.credits.balance ?? "—")}
                </code>
              </Row>
            )}
          </div>
        )}
      </Section>
    </>
  );
}
