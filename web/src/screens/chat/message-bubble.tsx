/**
 * Renders a single WireMessage. User bubbles right-aligned, assistant
 * left-aligned. Streaming assistant content gets the shimmer treatment
 * until `streamingFinished`.
 */
import { useMemo } from "react";
import type { WireMessage, WireTimelineEntry } from "../../bridge/wire";
import { WorkSummary } from "./work-items";
import cx from "../../lib/cx";

export function MessageBubble({ message }: { message: WireMessage }) {
  const isUser = message.role === "user";
  const streaming = !message.streamingFinished;

  return (
    <div className={cx("flex w-full", isUser ? "justify-end" : "justify-start")}>
      <div className={cx("max-w-[760px] flex flex-col gap-2", isUser ? "items-end" : "items-start")}>
        {message.workSummary && !isUser && <WorkSummary summary={message.workSummary} />}

        {message.timeline.length > 0 && !isUser && (
          <div className="space-y-2 w-full">
            {message.timeline.map((entry) => (
              <TimelineEntry key={timelineKey(entry)} entry={entry} />
            ))}
          </div>
        )}

        {message.reasoningText && !isUser && (
          <ReasoningBlock text={message.reasoningText} streaming={streaming} />
        )}

        {message.content && (
          <div
            style={{
              borderRadius: 14,
              boxShadow: isUser ? "inset 0 0 0 0.5px rgba(255,255,255,0.10)" : undefined,
            }}
            className={cx(
              "px-3.5 py-2.5 text-[14px] leading-[1.55] whitespace-pre-wrap break-words",
              isUser
                ? "bg-[var(--color-card)] text-[var(--color-fg)]"
                : "text-[var(--color-fg)]",
              message.isError && "text-[var(--color-destructive)]",
            )}
          >
            {streaming && !isUser ? <span className="shimmer-text">{message.content}</span> : message.content}
          </div>
        )}

        {message.attachments.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {message.attachments.map((a) => (
              <AttachmentChip key={a.id} attachment={a} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function TimelineEntry({ entry }: { entry: WireTimelineEntry }) {
  if (entry.type === "reasoning") {
    return <ReasoningBlock text={entry.text} streaming={false} />;
  }
  if (entry.type === "message") {
    return (
      <div className="text-[14px] leading-[1.55] whitespace-pre-wrap break-words">{entry.text}</div>
    );
  }
  if (entry.type === "tools") {
    return <WorkSummary summary={{ startedAt: new Date().toISOString(), items: entry.items }} />;
  }
  return null;
}

function ReasoningBlock({ text, streaming }: { text: string; streaming: boolean }) {
  return (
    <div
      className={cx(
        "rounded-[12px] border border-[var(--color-border)] bg-[var(--color-card)] px-3 py-2 text-[12.5px] leading-[1.55] whitespace-pre-wrap font-mono text-[var(--color-fg-secondary)]",
        streaming && "animate-pulse",
      )}
    >
      {text}
    </div>
  );
}

function AttachmentChip({ attachment }: { attachment: WireMessage["attachments"][number] }) {
  const dataUrl = useMemo(
    () => `data:${attachment.mimeType};base64,${attachment.dataBase64}`,
    [attachment],
  );
  if (attachment.kind === "image") {
    return (
      <img
        src={dataUrl}
        alt={attachment.filename ?? "image"}
        className="max-h-[180px] rounded-[10px] border border-[var(--color-border)]"
      />
    );
  }
  return (
    <audio controls src={dataUrl} className="h-9" />
  );
}

function timelineKey(entry: WireTimelineEntry): string {
  return `${entry.type}-${entry.id}`;
}
