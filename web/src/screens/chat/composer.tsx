// Composer mirrors ComposerView from the Mac. Auto-grow textarea, send
// button (white circle with ArrowUpIcon), interrupt (StopSquircle), mic,
// attachments. Layout follows the Mac: rounded chrome with tinted fill,
// hairline stroke, soft top blur on the page edge.
import { useEffect, useRef, useState } from "react";
import { useBridgeStore } from "../../bridge/store";
import {
  ArrowUpIcon,
  StopSquircle,
  FileChipIcon,
  PlusIcon,
  MicIcon,
} from "../../icons";
import cx from "../../lib/cx";
import { storage, StorageKeys } from "../../lib/storage";

interface Props {
  chatId: string | null;
  hasActiveTurn: boolean;
}

interface Attachment {
  id: string;
  filename: string;
  mimeType: string;
  base64: string;
  kind: "image" | "audio";
}

export function Composer({ chatId, hasActiveTurn }: Props) {
  const sendPrompt = useBridgeStore((s) => s.sendPrompt);
  const newChat = useBridgeStore((s) => s.newChat);
  const interruptTurn = useBridgeStore((s) => s.interruptTurn);
  const transcribeAudio = useBridgeStore((s) => s.transcribeAudio);
  const client = useBridgeStore((s) => s.client);

  const [text, setText] = useState(() => storage.get<string>(StorageKeys.composerDraft) ?? "");
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [recording, setRecording] = useState(false);
  const [busyTranscribing, setBusyTranscribing] = useState(false);
  const taRef = useRef<HTMLTextAreaElement | null>(null);
  const recRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);

  useEffect(() => {
    storage.set(StorageKeys.composerDraft, text);
  }, [text]);

  useEffect(() => {
    autoGrow(taRef.current);
  }, [text]);

  useEffect(() => {
    if (!client) return;
    return client.onFrame("transcriptionResult", (frame) => {
      setBusyTranscribing(false);
      if (frame.errorMessage) {
        console.error("transcribe error", frame.errorMessage);
        return;
      }
      setText((t) => (t.length > 0 ? `${t} ${frame.text}` : frame.text));
    });
  }, [client]);

  function send() {
    const body = text.trim();
    if (!body && attachments.length === 0) return;
    if (chatId) {
      sendPrompt(chatId, body, attachments.map(toWireAttachment));
    } else {
      newChat(body, attachments.map(toWireAttachment));
    }
    setText("");
    setAttachments([]);
    storage.remove(StorageKeys.composerDraft);
  }

  function onKeyDown(ev: React.KeyboardEvent<HTMLTextAreaElement>) {
    const composing = (ev.nativeEvent as KeyboardEvent).isComposing;
    if (ev.key === "Enter" && !ev.shiftKey && !composing) {
      ev.preventDefault();
      send();
    }
  }

  async function toggleRecord() {
    if (recording) {
      recRef.current?.stop();
      setRecording(false);
      return;
    }
    if (typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) return;
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const rec = new MediaRecorder(stream, { mimeType: "audio/webm" });
    chunksRef.current = [];
    rec.ondataavailable = (e) => { if (e.data.size > 0) chunksRef.current.push(e.data); };
    rec.onstop = async () => {
      stream.getTracks().forEach((t) => t.stop());
      const blob = new Blob(chunksRef.current, { type: "audio/webm" });
      const base64 = await blobToBase64(blob);
      setBusyTranscribing(true);
      transcribeAudio(base64, "audio/webm");
    };
    rec.start();
    recRef.current = rec;
    setRecording(true);
  }

  async function attachFile(files: FileList | null) {
    if (!files) return;
    const next: Attachment[] = [];
    for (const f of files) {
      const base64 = await fileToBase64(f);
      next.push({
        id: crypto.randomUUID(),
        filename: f.name,
        mimeType: f.type || "application/octet-stream",
        base64,
        kind: f.type.startsWith("audio/") ? "audio" : "image",
      });
    }
    setAttachments((cur) => [...cur, ...next]);
  }

  return (
    <div className="px-4 pb-4 pt-2">
      <div
        className="max-w-[920px] mx-auto p-3"
        style={{
          background: "var(--color-card)",
          borderRadius: 18,
          boxShadow:
            "inset 0 0 0 0.5px rgba(255,255,255,0.10), 0 8px 24px rgba(0,0,0,0.30)",
        }}
      >
        {attachments.length > 0 && (
          <div className="flex flex-wrap gap-2 mb-2">
            {attachments.map((a) => (
              <span
                key={a.id}
                className="inline-flex items-center gap-1.5 h-7 pl-2 pr-1.5 text-[12px]"
                style={{
                  borderRadius: 8,
                  background: "var(--color-card-hover)",
                  fontVariationSettings: '"wght" 700',
                }}
              >
                <FileChipIcon size={12} color="var(--color-fg-secondary)" />
                <span className="max-w-[180px] truncate">{a.filename}</span>
                <button
                  onClick={() => setAttachments((cur) => cur.filter((x) => x.id !== a.id))}
                  className="size-5 grid place-items-center hover:bg-[rgba(255,255,255,0.08)]"
                  style={{ borderRadius: 6, color: "var(--color-fg-secondary)" }}
                  aria-label="Remove attachment"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        )}
        <textarea
          ref={taRef}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKeyDown}
          rows={1}
          placeholder={chatId ? "Reply to Codex" : "Start a new conversation"}
          spellCheck={false}
          className="thin-scroll w-full bg-transparent outline-none resize-none"
          style={{
            fontSize: 14,
            lineHeight: 1.55,
            color: "var(--color-fg)",
            maxHeight: 260,
            fontVariationSettings: '"wght" 600',
          }}
        />
        <div className="flex items-center justify-between mt-2">
          <div className="flex items-center gap-1">
            <label
              className="size-8 grid place-items-center cursor-pointer transition-colors"
              style={{
                color: "var(--color-fg-secondary)",
                borderRadius: 999,
              }}
              onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.06)")}
              onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
            >
              <input type="file" className="hidden" multiple onChange={(e) => attachFile(e.target.files)} />
              <PlusIcon size={14} />
            </label>
            <button
              type="button"
              onClick={toggleRecord}
              className={cx(
                "size-8 grid place-items-center transition-colors",
                recording && "bg-[var(--color-destructive-fill)]",
              )}
              style={{
                borderRadius: 999,
                color: recording ? "var(--color-destructive)" : "var(--color-fg-secondary)",
              }}
              title="Voice"
            >
              <MicIcon size={14} />
            </button>
            {busyTranscribing && (
              <span className="text-[11px]" style={{ color: "var(--color-fg-secondary)" }}>
                Transcribing…
              </span>
            )}
          </div>
          {hasActiveTurn ? (
            <button
              onClick={() => chatId && interruptTurn(chatId)}
              className="size-8 grid place-items-center transition-opacity"
              style={{ borderRadius: 999, background: "#ffffff" }}
              title="Stop"
            >
              <StopSquircle size={12} color="#000" />
            </button>
          ) : (
            <button
              onClick={send}
              disabled={!text.trim() && attachments.length === 0}
              className="size-8 grid place-items-center transition-opacity disabled:opacity-40"
              style={{ borderRadius: 999, background: "#ffffff" }}
              title="Send"
            >
              <ArrowUpIcon size={14} color="#000" strokeWidth={2.6} />
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function autoGrow(el: HTMLTextAreaElement | null) {
  if (!el) return;
  el.style.height = "auto";
  el.style.height = Math.min(el.scrollHeight, 260) + "px";
}

async function blobToBase64(blob: Blob): Promise<string> {
  const buf = await blob.arrayBuffer();
  let binary = "";
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]!);
  return btoa(binary);
}

async function fileToBase64(file: File): Promise<string> {
  return blobToBase64(file);
}

function toWireAttachment(a: Attachment) {
  return {
    id: a.id,
    kind: a.kind,
    mimeType: a.mimeType,
    filename: a.filename,
    dataBase64: a.base64,
  };
}
