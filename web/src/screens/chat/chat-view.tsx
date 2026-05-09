/**
 * ChatView mirrors `ChatView` from the macOS app. Streams messages from
 * the BridgeStore, supports lazy "load older" pagination when the user
 * scrolls near the top, and shows the empty/no-chat state.
 */
import { useEffect, useLayoutEffect, useRef } from "react";
import { useBridgeStore } from "../../bridge/store";
import { MessageBubble } from "./message-bubble";
import { Composer } from "./composer";
import { BotIcon, ChatIcon } from "../../icons";

interface Props {
  chatId: string | null;
}

export function ChatView({ chatId }: Props) {
  const messages = useBridgeStore((s) => (chatId ? s.messagesByChat[chatId] ?? [] : []));
  const chats = useBridgeStore((s) => s.chats);
  const openChat = useBridgeStore((s) => s.openChat);
  const loadOlder = useBridgeStore((s) => s.loadOlderMessages);
  const hasMore = useBridgeStore((s) => (chatId ? s.hasMoreByChat[chatId] ?? false : false));
  const chat = chats.find((c) => c.id === chatId) ?? null;

  const scrollerRef = useRef<HTMLDivElement | null>(null);
  const lastChatRef = useRef<string | null>(null);
  const lastCountRef = useRef(0);

  useEffect(() => {
    if (chatId && lastChatRef.current !== chatId) {
      lastChatRef.current = chatId;
      openChat(chatId);
    }
  }, [chatId, openChat]);

  // Auto-scroll to bottom on first paint of a chat or when a new message
  // is appended (but not when loading older messages prepends).
  useLayoutEffect(() => {
    if (!scrollerRef.current) return;
    if (messages.length > lastCountRef.current) {
      const wasNearBottom =
        scrollerRef.current.scrollHeight - scrollerRef.current.scrollTop - scrollerRef.current.clientHeight < 200;
      if (wasNearBottom || lastCountRef.current === 0) {
        scrollerRef.current.scrollTop = scrollerRef.current.scrollHeight;
      }
    }
    lastCountRef.current = messages.length;
  }, [messages]);

  useEffect(() => {
    const el = scrollerRef.current;
    if (!el || !hasMore || !chatId) return;
    const onScroll = () => {
      if (el.scrollTop < 80) loadOlder(chatId);
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => el.removeEventListener("scroll", onScroll);
  }, [chatId, hasMore, loadOlder]);

  if (!chatId) {
    return (
      <div className="h-full flex flex-col">
        <div className="flex-1 grid place-items-center text-center px-6">
          <div className="max-w-md space-y-3">
            <div className="size-14 mx-auto rounded-[18px] bg-[var(--color-bg-elev-2)] grid place-items-center text-[var(--color-fg)]">
              <BotIcon size={28} />
            </div>
            <div className="text-[18px] font-medium tracking-[-0.02em]">Start a new conversation</div>
            <div className="text-[13px] text-[var(--color-fg-muted)] leading-relaxed">
              Pick a chat from the sidebar or write below to start a new one. Codex runs on your Mac;
              this page is just a window.
            </div>
          </div>
        </div>
        <Composer chatId={null} hasActiveTurn={false} />
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col">
      <header className="h-[56px] px-5 flex items-center justify-between border-b border-[var(--color-border)] bg-[var(--color-bg)]/70 backdrop-blur-xl">
        <div className="flex items-center gap-2">
          <ChatIcon size={14} className="text-[var(--color-fg-muted)]" />
          <h1 className="text-[14px] font-medium tracking-[-0.01em]">{chat?.title ?? "Untitled"}</h1>
        </div>
        {chat?.cwd && (
          <div className="font-mono text-[11.5px] text-[var(--color-fg-muted)] truncate max-w-[420px]">
            {chat.cwd}
            {chat.branch ? ` · ${chat.branch}` : ""}
          </div>
        )}
      </header>

      <div ref={scrollerRef} className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[920px] mx-auto px-6 py-6 space-y-6">
          {hasMore && (
            <div className="text-center text-[11px] text-[var(--color-fg-dim)]">Loading older…</div>
          )}
          {messages.length === 0 ? (
            <div className="text-center text-[12.5px] text-[var(--color-fg-muted)] py-12">No messages yet</div>
          ) : (
            messages.map((m) => <MessageBubble key={m.id} message={m} />)
          )}
        </div>
      </div>

      <Composer chatId={chatId} hasActiveTurn={chat?.hasActiveTurn ?? false} />
    </div>
  );
}
