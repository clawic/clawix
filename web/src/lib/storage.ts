/**
 * Tiny typed wrapper over localStorage. Used for persisting the pairing
 * token and the SPA's lightweight UI prefs. Never used for secrets, chats
 * or messages: those come from the daemon on every connection (no cache
 * invalidation hell, by design).
 */
const PREFIX = "clawix.web.";

export const storage = {
  get<T = string>(key: string): T | null {
    try {
      const raw = localStorage.getItem(PREFIX + key);
      if (raw == null) return null;
      return JSON.parse(raw) as T;
    } catch {
      return null;
    }
  },
  set<T>(key: string, value: T): void {
    try {
      localStorage.setItem(PREFIX + key, JSON.stringify(value));
    } catch {
      // ignore quota / privacy mode
    }
  },
  remove(key: string): void {
    try {
      localStorage.removeItem(PREFIX + key);
    } catch {
      /* noop */
    }
  },
};

export const StorageKeys = {
  bearer: "bridge.bearer",
  deviceName: "bridge.deviceName",
  lastChatId: "ui.lastChatId",
  composerDraft: "ui.composerDraft",
  vaultUnlockedAt: "secrets.unlockedAt",
} as const;
