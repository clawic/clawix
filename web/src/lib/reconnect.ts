/**
 * Exponential backoff with cap, used by BridgeClient when a WebSocket
 * connection drops. Mirrors the pattern in the iOS BridgeClient: 1, 2, 4, 8,
 * 16, 30 seconds, then sticks at 30. Reset on every successful authOk.
 */
export class Backoff {
  private attempt = 0;
  constructor(
    private readonly base = 1000,
    private readonly cap = 30_000,
  ) {}

  next(): number {
    const delay = Math.min(this.cap, this.base * 2 ** this.attempt);
    this.attempt++;
    const jitter = Math.random() * 0.25 * delay;
    return Math.round(delay + jitter);
  }

  reset(): void {
    this.attempt = 0;
  }

  current(): number {
    return Math.min(this.cap, this.base * 2 ** this.attempt);
  }
}
