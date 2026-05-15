/**
 * WebSocket bridge client. Mirrors the iOS BridgeClient at
 * `clawix/ios/Sources/Clawix/Bridge/BridgeClient.swift`:
 *
 *   1. open WS to `${endpoint}/ws`
 *   2. send `auth` frame (token + deviceName + clientKind + stable client ids)
 *   3. wait for `authOk` (or `authFailed` / `versionMismatch`)
 *   4. push subsequent frames to listeners; reconnect with exponential
 *      backoff on close.
 *
 * The web client is read-mostly, so it authenticates as `clientKind: "companion"`.
 */

import {
  BRIDGE_SCHEMA_VERSION,
  type BridgeFrame,
  type FrameBody,
  type FrameOf,
  type FrameType,
  decodeFrame,
  encodeFrame,
  peekSchemaVersion,
} from "./frames";
import { Backoff } from "../lib/reconnect";

export type ConnectionState =
  | { kind: "idle" }
  | { kind: "connecting" }
  | { kind: "authenticating" }
  | { kind: "ready"; hostDisplayName: string | null }
  | { kind: "auth-failed"; reason: string }
  | { kind: "version-mismatch"; serverVersion: number }
  | { kind: "offline"; reason: string; retryAt: number };

export interface BridgeClientOptions {
  /** WebSocket endpoint, defaults to `${location.origin}/ws` mapped to ws/wss. */
  endpoint?: string;
  /** Bearer token from QR scan or short-code paste. */
  token: string;
  deviceName?: string;
  /** Override the heartbeat interval; default 15s like iOS BridgeClient. */
  heartbeatMs?: number;
  /** Override the silence threshold; default 30s. */
  deadAfterMs?: number;
}

type Listener = (frame: BridgeFrame) => void;
type StateListener = (state: ConnectionState) => void;

interface BridgeBootstrap {
  wsPort?: number;
  schemaVersion?: number;
}

function defaultEndpoint(): string {
  if (typeof window === "undefined") return "ws://localhost:24080/ws";
  const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
  const bootstrap = (window as Window & { __CLAWIX_BRIDGE__?: BridgeBootstrap }).__CLAWIX_BRIDGE__;
  if (bootstrap?.wsPort) {
    const hostname = window.location.hostname || "localhost";
    return `${proto}//${hostname}:${bootstrap.wsPort}/ws`;
  }
  // Vite dev server proxies /ws to the daemon, so same-origin works in dev.
  // Embedded mode injects the bootstrap snippet, so we never reach this branch
  // when served from the daemon.
  const host = window.location.host || "localhost:24080";
  return `${proto}//${host}/ws`;
}

function randomId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `web-${Math.random().toString(36).slice(2)}-${Date.now().toString(36)}`;
}

function persistedId(key: string): string {
  if (typeof window === "undefined") return randomId();
  const storageKey = `clawix.bridge.${key}`;
  try {
    const existing = window.localStorage.getItem(storageKey);
    if (existing) return existing;
    const value = randomId();
    window.localStorage.setItem(storageKey, value);
    return value;
  } catch {
    return randomId();
  }
}

export class BridgeClient {
  private ws: WebSocket | null = null;
  private state: ConnectionState = { kind: "idle" };
  private readonly listeners = new Set<Listener>();
  private readonly stateListeners = new Set<StateListener>();
  private readonly backoff = new Backoff(1_000, 30_000);
  private heartbeat: ReturnType<typeof setInterval> | null = null;
  private deadTimer: ReturnType<typeof setTimeout> | null = null;
  private lastInbound = Date.now();
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private stopped = false;

  constructor(private readonly opts: BridgeClientOptions) {}

  start(): void {
    this.stopped = false;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    this.clearTimers();
    if (this.ws) {
      try { this.ws.close(1000, "client-stop"); } catch { /* ignore */ }
      this.ws = null;
    }
    this.setState({ kind: "idle" });
  }

  send(body: FrameBody): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    if (this.state.kind !== "ready" && body.type !== "auth") return;
    this.ws.send(encodeFrame(body));
  }

  on(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  onState(listener: StateListener): () => void {
    this.stateListeners.add(listener);
    listener(this.state);
    return () => this.stateListeners.delete(listener);
  }

  /** Convenience helper: subscribe to one frame type only. */
  onFrame<T extends FrameType>(type: T, fn: (frame: FrameOf<T>) => void): () => void {
    return this.on((frame) => {
      if (frame.type === type) fn(frame as FrameOf<T>);
    });
  }

  getState(): ConnectionState {
    return this.state;
  }

  private connect(): void {
    if (this.stopped) return;
    const url = this.opts.endpoint ?? defaultEndpoint();
    this.setState({ kind: "connecting" });
    let ws: WebSocket;
    try {
      ws = new WebSocket(url);
    } catch (err) {
      this.scheduleReconnect(`open-failed: ${(err as Error).message}`);
      return;
    }
    this.ws = ws;
    ws.binaryType = "arraybuffer";

    ws.onopen = () => {
      this.setState({ kind: "authenticating" });
      this.lastInbound = Date.now();
      ws.send(
        encodeFrame({
          type: "auth",
          token: this.opts.token,
          deviceName: this.opts.deviceName ?? this.guessDeviceName(),
          clientKind: "companion",
          clientId: "clawix.web.companion",
          installationId: persistedId("installationId"),
          deviceId: persistedId("deviceId"),
        }),
      );
      this.startHeartbeat();
    };

    ws.onmessage = (ev) => {
      this.lastInbound = Date.now();
      this.armDeadTimer();
      const raw = typeof ev.data === "string" ? ev.data : "";
      if (!raw) return;

      const peeked = peekSchemaVersion(raw);
      if (peeked != null && peeked > BRIDGE_SCHEMA_VERSION) {
        this.setState({ kind: "version-mismatch", serverVersion: peeked });
        try { ws.close(1000, "version-mismatch"); } catch { /* ignore */ }
        return;
      }

      const frame = decodeFrame(raw);
      if (!frame) return;

      switch (frame.type) {
        case "authOk":
          this.backoff.reset();
          this.setState({ kind: "ready", hostDisplayName: frame.hostDisplayName ?? null });
          break;
        case "authFailed":
          this.setState({ kind: "auth-failed", reason: frame.reason });
          try { ws.close(1000, "auth-failed"); } catch { /* ignore */ }
          return;
        case "versionMismatch":
          this.setState({ kind: "version-mismatch", serverVersion: frame.serverVersion });
          try { ws.close(1000, "version-mismatch"); } catch { /* ignore */ }
          return;
        default:
          break;
      }

      for (const listener of this.listeners) {
        try { listener(frame); } catch (err) {
          console.error("[BridgeClient] listener threw", err);
        }
      }
    };

    ws.onerror = () => {
      // Browser hides cause; treat as transient and let onclose schedule retry.
    };

    ws.onclose = (ev) => {
      this.clearTimers();
      this.ws = null;
      if (this.state.kind === "auth-failed" || this.state.kind === "version-mismatch") {
        return;
      }
      this.scheduleReconnect(`closed code=${ev.code}`);
    };
  }

  private scheduleReconnect(reason: string): void {
    if (this.stopped) return;
    const delay = this.backoff.next();
    this.setState({ kind: "offline", reason, retryAt: Date.now() + delay });
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
  }

  private startHeartbeat(): void {
    const interval = this.opts.heartbeatMs ?? 15_000;
    if (this.heartbeat) clearInterval(this.heartbeat);
    this.heartbeat = setInterval(() => {
      if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
      try {
        // The Swift server uses `autoReplyPing` on NWProtocolWebSocket, so
        // we do not need to send WS-layer pings (the browser's WebSocket API
        // doesn't expose ping anyway). Instead we rely on the server's own
        // traffic and the deadTimer to detect a stale link.
      } catch {
        /* ignore */
      }
    }, interval);
    this.armDeadTimer();
  }

  private armDeadTimer(): void {
    const dead = this.opts.deadAfterMs ?? 30_000;
    if (this.deadTimer) clearTimeout(this.deadTimer);
    this.deadTimer = setTimeout(() => {
      const idle = Date.now() - this.lastInbound;
      if (idle >= dead && this.ws) {
        try { this.ws.close(4000, "dead-link"); } catch { /* ignore */ }
      }
    }, dead);
  }

  private clearTimers(): void {
    if (this.heartbeat) clearInterval(this.heartbeat);
    if (this.deadTimer) clearTimeout(this.deadTimer);
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.heartbeat = null;
    this.deadTimer = null;
    this.reconnectTimer = null;
  }

  private setState(state: ConnectionState): void {
    this.state = state;
    for (const listener of this.stateListeners) {
      try { listener(state); } catch (err) {
        console.error("[BridgeClient] state listener threw", err);
      }
    }
  }

  private guessDeviceName(): string {
    if (typeof navigator === "undefined") return "Web";
    const ua = navigator.userAgent;
    const platform = (navigator as Navigator & { platform?: string }).platform ?? "";
    if (/iPhone|iPad|iPod/.test(ua)) return "iOS Web";
    if (/Android/.test(ua)) return "Android Web";
    if (/Mac/.test(platform)) return "Mac Web";
    if (/Win/.test(platform)) return "Windows Web";
    if (/Linux/.test(platform)) return "Linux Web";
    return "Web";
  }
}
