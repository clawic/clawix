// macOS-style pill toggle. Capsule track, animated knob.
// Mirror of SettingsView.swift PillToggle (272-315).
import cx from "../../lib/cx";

interface Props {
  isOn: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
}

export function PillToggle({ isOn, onChange, disabled }: Props) {
  return (
    <button
      role="switch"
      aria-checked={isOn}
      disabled={disabled}
      onClick={() => onChange(!isOn)}
      className={cx(
        "relative inline-flex items-center transition-[background-color] duration-[150ms] ease-[var(--ease-row)]",
        "disabled:opacity-40",
      )}
      style={{
        width: 32,
        height: 20,
        borderRadius: 999,
        background: isOn ? "rgba(255,255,255,0.85)" : "rgba(255,255,255,0.12)",
        boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.10)",
      }}
    >
      <span
        className="block transition-[transform] duration-[150ms] ease-[var(--ease-row)]"
        style={{
          width: 16,
          height: 16,
          borderRadius: 999,
          background: isOn ? "#101010" : "#dcdcdc",
          transform: `translateX(${isOn ? 14 : 2}px)`,
        }}
      />
    </button>
  );
}
