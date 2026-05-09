/**
 * Composer mirrors `ComposerView` from the macOS app: text area with
 * auto-grow, send button, mic button (Web Audio recording → daemon
 * transcription), attachment chips. Stop button replaces send while a
 * turn is active.
 */
import { useEffect, useRef, useState } from "react";
import { useBridgeStore } from "../../bridge/store";
import { MicIcon, SendIcon, StopIcon, FileChipIcon, PlusIcon } from "../../icons";
import cx from "../../lib/cx";
import { GlassPill } from "../../components/glass-pill";
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
      <div className="max-w-[920px] mx-auto rounded-[20px] bg-[var(--color-bg-elev-1)] border border-[var(--color-border)] focus-within:border-[var(--color-border-strong)] transition-colors p-3 space-y-2">
        {attachments.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {attachments.map((a) => (
              <span
                key={a.id}
                className="inline-flex items-center gap-1.5 h-7 pl-2 pr-1.5 rounded-[8px] bg-[var(--color-bg-elev-3)] text-[12px]"
              >
                <FileChipIcon size={12} className="text-[var(--color-fg-muted)]" />
                <span className="max-w-[180px] truncate">{a.filename}</span>
                <button
                  onClick={() => setAttachments((cur) => cur.filter((x) => x.id !== a.id))}
                  className="size-5 rounded-md hover:bg-[var(--color-bg-elev-2)] grid place-items-center text-[var(--color-fg-muted)]"
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
          className="thin-scroll w-full bg-transparent outline-none resize-none text-[14px] leading-[1.55] placeholder:text-[var(--color-fg-dim)] max-h-[260px]"
        />
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-1.5">
            <label className="size-8 rounded-full hover:bg-[var(--color-bg-elev-2)] grid place-items-center cursor-pointer text-[var(--color-fg-muted)]">
              <input type="file" className="hidden" multiple onChange={(e) => attachFile(e.target.files)} />
              <PlusIcon size={14} />
            </label>
            <button
              type="button"
              onClick={toggleRecord}
              className={cx(
                "size-8 rounded-full grid place-items-center transition-colors",
                recording
                  ? "bg-[var(--color-danger)]/20 text-[var(--color-danger)]"
                  : "hover:bg-[var(--color-bg-elev-2)] text-[var(--color-fg-muted)]",
              )}
              title="Voice"
            >
              <MicIcon size={14} />
            </button>
            {busyTranscribing && (
              <span className="text-[11px] text-[var(--color-fg-muted)]">Transcribing…</span>
            )}
          </div>
          {hasActiveTurn ? (
            <GlassPill size="sm" onClick={() => chatId && interruptTurn(chatId)}>
              <StopIcon size={10} /> Stop
            </GlassPill>
          ) : (
            <GlassPill size="sm" onClick={send} disabled={!text.trim() && attachments.length === 0}>
              Send <SendIcon size={12} />
            </GlassPill>
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
