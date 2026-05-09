// ChatView mirrors ChatView.swift. Header with chat title + cwd/branch
// info; scrollable messages list; composer pinned to the bottom.
import { useEffect, useLayoutEffect, useRef } from "react";
import { useBridgeStore } from "../../bridge/store";
import { MessageBubble } from "./message-bubble";
import { Composer } from "./composer";
import { ClawixLogoIcon, ChatIcon } from "../../icons";

interface Props {
  chatId: string | null;
}

const EMPTY_MESSAGES: ReturnType<typeof useBridgeStore.getState>["messagesByChat"][string] = [];

export function ChatView({ chatId }: Props) {
  const messages = useBridgeStore((s) => (chatId ? s.messagesByChat[chatId] ?? EMPTY_MESSAGES : EMPTY_MESSAGES));
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
          <div className="max-w-md flex flex-col items-center gap-4">
            <ClawixLogoIcon size={56} color="var(--color-fg)" />
            <div
              style={{
                fontSize: 18,
                fontVariationSettings: '"wght" 800',
                letterSpacing: "-0.02em",
              }}
            >
              Start a new conversation
            </div>
            <div
              style={{
                fontSize: 13,
                color: "var(--color-fg-secondary)",
                lineHeight: 1.55,
                fontVariationSettings: '"wght" 600',
              }}
            >
              Pick a chat from the sidebar or write below to start a new one. Codex runs on your Mac;
              this page is a window into it.
            </div>
          </div>
        </div>
        <Composer chatId={null} hasActiveTurn={false} />
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col">
      <header
        className="px-5 flex items-center justify-between"
        style={{
          height: 56,
          borderBottom: "0.5px solid var(--color-popup-stroke)",
        }}
      >
        <div className="flex items-center gap-2">
          <ChatIcon size={14} className="text-[var(--color-fg-secondary)]" />
          <h1
            style={{
              fontSize: 14,
              fontVariationSettings: '"wght" 700',
              letterSpacing: "-0.01em",
            }}
          >
            {chat?.title ?? "Untitled"}
          </h1>
        </div>
        {chat?.cwd && (
          <div
            className="font-mono truncate max-w-[420px]"
            style={{
              fontSize: 11.5,
              color: "var(--color-fg-secondary)",
            }}
          >
            {chat.cwd}
            {chat.branch ? ` · ${chat.branch}` : ""}
          </div>
        )}
      </header>

      <div ref={scrollerRef} className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[920px] mx-auto px-6 py-6 space-y-6">
          {hasMore && (
            <div
              className="text-center"
              style={{ fontSize: 11, color: "var(--color-fg-tertiary)" }}
            >
              Loading older…
            </div>
          )}
          {messages.length === 0 ? (
            <div
              className="text-center py-12"
              style={{ fontSize: 12.5, color: "var(--color-fg-secondary)" }}
            >
              No messages yet
            </div>
          ) : (
            messages.map((m) => <MessageBubble key={m.id} message={m} />)
          )}
        </div>
      </div>

      <Composer chatId={chatId} hasActiveTurn={chat?.hasActiveTurn ?? false} />
    </div>
  );
}
