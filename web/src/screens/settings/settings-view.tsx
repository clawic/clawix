// Settings mirrors the Mac SettingsView: PageHeader, SectionLabel, Card,
// CardDivider rows. SlidingSegmented for the tab strip.
import { useState } from "react";
import { useBridgeStore } from "../../bridge/store";
import { SlidingSegmented } from "../../components/sliding-segmented";
import { PageHeader, SectionLabel, Card, CardDivider, Button } from "../../components/ui";
import { storage, StorageKeys } from "../../lib/storage";

type Tab = "general" | "appearance" | "advanced";

export function SettingsView() {
  const [tab, setTab] = useState<Tab>("general");
  return (
    <div className="h-full flex flex-col">
      <header
        className="px-6 flex items-center gap-4"
        style={{
          height: 56,
          borderBottom: "0.5px solid var(--color-popup-stroke)",
        }}
      >
        <h1
          style={{
            fontSize: 15,
            fontVariationSettings: '"wght" 700',
            letterSpacing: "-0.01em",
          }}
        >
          Settings
        </h1>
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
        <div className="max-w-[720px] mx-auto pt-8 pb-12 px-6">
          <PageHeader
            title={
              tab === "general" ? "General" : tab === "appearance" ? "Appearance" : "Advanced"
            }
            subtitle={
              tab === "general"
                ? "Pairing, identity, Mac-only affordances."
                : tab === "appearance"
                ? "Theme. Web matches the Mac dark palette."
                : "Bridge runtime, rate limits, diagnostics."
            }
          />
          {tab === "general" && <GeneralSettings />}
          {tab === "appearance" && <AppearanceSettings />}
          {tab === "advanced" && <AdvancedSettings />}
        </div>
      </div>
    </div>
  );
}

function GeneralSettings() {
  const hostDisplayName = useBridgeStore((s) => s.hostDisplayName);
  const detach = useBridgeStore((s) => s.detach);
  const [deviceName, setDeviceName] = useState(() => storage.get<string>(StorageKeys.deviceName) ?? "");

  return (
    <>
      <SectionLabel>Connection</SectionLabel>
      <Card>
        <Row label="Paired with" hint={hostDisplayName ? `Currently bonded to ${hostDisplayName}` : "Not paired"}>
          <code style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>{hostDisplayName ?? "—"}</code>
        </Row>
        <CardDivider />
        <Row label="Device label" hint="Shown in the Mac app's connected peers list.">
          <input
            value={deviceName}
            onChange={(e) => {
              setDeviceName(e.target.value);
              storage.set(StorageKeys.deviceName, e.target.value);
            }}
            placeholder="Web"
            style={{
              height: 32,
              width: 220,
              padding: "0 12px",
              borderRadius: 8,
              background: "rgba(255,255,255,0.06)",
              boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.10)",
              outline: "none",
              fontSize: 13,
              color: "var(--color-fg)",
              fontVariationSettings: '"wght" 600',
            }}
          />
        </Row>
        <CardDivider />
        <Row label="Unpair this browser" hint="Clears the local token. You will need to enter the short code again.">
          <Button
            variant="destructive"
            onClick={() => {
              storage.remove(StorageKeys.bearer);
              detach();
              window.location.reload();
            }}
          >
            Unpair
          </Button>
        </Row>
      </Card>

      <SectionLabel>Mac-only</SectionLabel>
      <Card>
        <Row label="Global dictation hotkey">
          <span style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>Manage on Mac</span>
        </Row>
        <CardDivider />
        <Row label="Menu bar item">
          <span style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>Manage on Mac</span>
        </Row>
        <CardDivider />
        <Row label="Open at login">
          <span style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>Manage on Mac</span>
        </Row>
      </Card>
    </>
  );
}

function AppearanceSettings() {
  return (
    <>
      <SectionLabel>Theme</SectionLabel>
      <Card>
        <Row
          label="Color scheme"
          hint="Web matches the Mac, which is dark-only by design."
        >
          <span style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>Always dark</span>
        </Row>
      </Card>
    </>
  );
}

function AdvancedSettings() {
  const bridge = useBridgeStore((s) => s.bridge);
  const conn = useBridgeStore((s) => s.connection);
  const rl = useBridgeStore((s) => s.rateLimits);

  return (
    <>
      <SectionLabel>Bridge runtime</SectionLabel>
      <Card>
        <Row label="Daemon state">
          <code style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>{bridge.state}</code>
        </Row>
        <CardDivider />
        <Row label="Chat count">
          <code style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>{bridge.chatCount}</code>
        </Row>
        <CardDivider />
        <Row label="Connection">
          <code style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>{conn.kind}</code>
        </Row>
      </Card>

      <SectionLabel>Rate limits</SectionLabel>
      <Card>
        {!rl ? (
          <div style={{ padding: "12px 14px", fontSize: 12, color: "var(--color-fg-secondary)" }}>
            No data yet.
          </div>
        ) : (
          <>
            {rl.primary && (
              <>
                <Row label="Primary window">
                  <code style={{ fontSize: 12 }}>{rl.primary.usedPercent}% used</code>
                </Row>
                {(rl.secondary || rl.credits) && <CardDivider />}
              </>
            )}
            {rl.secondary && (
              <>
                <Row label="Secondary window">
                  <code style={{ fontSize: 12 }}>{rl.secondary.usedPercent}% used</code>
                </Row>
                {rl.credits && <CardDivider />}
              </>
            )}
            {rl.credits && (
              <Row label="Credits">
                <code
                  style={{
                    fontSize: 12,
                    color: rl.credits.unlimited ? "var(--color-banner-ok-fg)" : undefined,
                  }}
                >
                  {rl.credits.unlimited ? "Unlimited" : (rl.credits.balance ?? "—")}
                </code>
              </Row>
            )}
          </>
        )}
      </Card>
    </>
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
    <div className="flex items-center justify-between gap-6" style={{ padding: "12px 14px" }}>
      <div className="min-w-0 flex flex-col gap-[3px]">
        <div style={{ fontSize: 12.5, color: "var(--color-fg)" }}>{label}</div>
        {hint && (
          <div
            style={{
              fontSize: 11,
              color: "var(--color-fg-secondary)",
              fontVariationSettings: '"wght" 700',
              lineHeight: 1.4,
            }}
          >
            {hint}
          </div>
        )}
      </div>
      {children}
    </div>
  );
}
