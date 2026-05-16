type TimerMode = "idle" | "focus" | "paused" | "break" | "ended";

export type Mood = "focused" | "neutral" | "distracted";

export type PomodoroShortcut =
  | "Start recent focus"
  | "Start focus"
  | "Pause / unpause"
  | "Take a break"
  | "Finish Session"
  | "Abandon Session"
  | "Update intention"
  | "Current status";

export type PomodoroUrlCommand = "start" | "pause" | "finish" | "break" | "abandon" | "status";

export type PomodoroSoundSlot = "session" | "session-end" | "break" | "break-end";

export type PomodoroReportRange = "day" | "week" | "month";

export interface PomodoroCategory {
  id: string;
  name: string;
  color: string;
  archived?: boolean;
}

export interface BlockerRule {
  enabled: boolean;
  type: "deny" | "allow";
  entries: string;
}

interface AppBlockerRule {
  enabled: boolean;
  apps: string[];
}

export interface PomodoroSettings {
  dailyGoalMinutes: number;
  showSuggestionsBy: "all" | "category" | "recent";
  focusIntentionOnCategoryChange: boolean;
  autoStartSuggestion: boolean;
  snapIntervalMinutes: number;
  autoStartFocus: boolean;
  autoStartBreak: boolean;
  defaultMood: Mood;
  askReflection: boolean;
  sleepAction: "nothing" | "pause" | "finish";
  launchAtLogin: boolean;
  sessionMinutes: number;
  shortBreakMinutes: number;
  longBreakMinutes: number;
  longBreakAfterFocusMinutes: number;
  breathCount: number;
  sessionMainAction: "restart" | "break" | "idle";
  breakMainAction: "start-session" | "finish-break" | "idle";
  endingSoonEnabled: boolean;
  endingSoonMinutes: number;
  endingSoonSound: boolean;
  presenceEnabled: boolean;
  sessionOverflowEnabled: boolean;
  pauseOverflowEnabled: boolean;
  breakOverflowEnabled: boolean;
  overflowMinutes: number;
  backgroundSoundEnabled: boolean;
  sessionSound: string;
  sessionEndSound: string;
  breakSound: string;
  breakEndSound: string;
  sessionVolume: number;
  sessionEndVolume: number;
  breakVolume: number;
  breakEndVolume: number;
  sessionWebBlocker: BlockerRule;
  breakWebBlocker: BlockerRule;
  sessionAppBlocker: AppBlockerRule;
  breakAppBlocker: AppBlockerRule;
  slackBlockerEnabled: boolean;
  slackTeams: string[];
  menuShowDuration: boolean;
  menuShowCategory: boolean;
  menuShowTodayTotal: boolean;
  showDockIcon: boolean;
  keepWindowOnTop: boolean;
  keepWindowOnTopOnBreak: boolean;
  showOnAllSpaces: boolean;
  minimizeWhenStarted: boolean;
  showOnTimerEnd: boolean;
  windowTrackerEnabled: boolean;
  windowTrackers: WindowTrackerRule[];
  theme: "system" | "dark" | "light";
  language: string;
  localShortcutsEnabled: boolean;
  globalShortcutsEnabled: boolean;
  appleScriptEnabled: boolean;
  urlSchemeEnabled: boolean;
  developerTodoPreview: boolean;
}

interface WindowTrackerRule {
  id: string;
  appName: string;
  windowTitle: string;
  categoryId: string;
  intention: string;
}

export interface PomodoroTask {
  id: string;
  title: string;
  source: "manual" | "plain-text" | "things" | "linear" | "reminders";
  categoryId: string;
  estimateMinutes: number;
  done: boolean;
}

export interface PomodoroScheduleItem {
  id: string;
  title: string;
  categoryId: string;
  dateKey: string;
  startMinutes: number;
  durationMinutes: number;
  source: "manual" | "calendar" | "task";
  started?: boolean;
}

export interface PomodoroLog {
  id: string;
  kind: "focus" | "break";
  intention: string;
  categoryId: string;
  startAt: number;
  endAt: number;
  durationSec: number;
  pausesSec: number;
  mood?: Mood;
  notes?: string;
  abandoned?: boolean;
}

interface PomodoroActiveTimer {
  mode: TimerMode;
  kind?: "focus" | "break";
  intention: string;
  categoryId: string;
  startAt: number;
  endAt: number;
  totalSec: number;
  remainingSec: number;
  pausesSec: number;
  pausedAt?: number;
  noticesSent?: string[];
  notes: string;
}

interface PomodoroNotice {
  id: string;
  at: number;
  title: string;
  detail: string;
}

export interface PomodoroState {
  categories: PomodoroCategory[];
  tasks: PomodoroTask[];
  schedules: PomodoroScheduleItem[];
  logs: PomodoroLog[];
  settings: PomodoroSettings;
  active: PomodoroActiveTimer | null;
  intentionDraft: string;
  categoryId: string;
  selectedDate: string;
  notesOnly: boolean;
  reportFilter: "all" | "focus" | "break" | "notes";
  reportRange: PomodoroReportRange;
  miniPlayerOpen: boolean;
  notices: PomodoroNotice[];
  lastAbandoned?: PomodoroLog;
}

export function defaultPomodoroState(now = Date.now()): PomodoroState {
  const today = dateKey(now);
  const categories: PomodoroCategory[] = [
    { id: "general", name: "General", color: "#ef5b5b" },
    { id: "deep-work", name: "Deep work", color: "#73a6ff" },
    { id: "admin", name: "Admin", color: "#f1b85b" },
  ];

  return {
    categories,
    tasks: [],
    schedules: [],
    logs: [],
    settings: {
      dailyGoalMinutes: 120,
      showSuggestionsBy: "all",
      focusIntentionOnCategoryChange: true,
      autoStartSuggestion: true,
      snapIntervalMinutes: 5,
      autoStartFocus: false,
      autoStartBreak: false,
      defaultMood: "neutral",
      askReflection: false,
      sleepAction: "nothing",
      launchAtLogin: false,
      sessionMinutes: 25,
      shortBreakMinutes: 5,
      longBreakMinutes: 20,
      longBreakAfterFocusMinutes: 90,
      breathCount: 1,
      sessionMainAction: "restart",
      breakMainAction: "start-session",
      endingSoonEnabled: true,
      endingSoonMinutes: 2,
      endingSoonSound: true,
      presenceEnabled: false,
      sessionOverflowEnabled: true,
      pauseOverflowEnabled: true,
      breakOverflowEnabled: true,
      overflowMinutes: 10,
      backgroundSoundEnabled: false,
      sessionSound: "Clock Ticking",
      sessionEndSound: "Kitchen Timer",
      breakSound: "Ocean Waves",
      breakEndSound: "Gong",
      sessionVolume: 0.05,
      sessionEndVolume: 0.5,
      breakVolume: 0.5,
      breakEndVolume: 0.5,
      sessionWebBlocker: { enabled: false, type: "deny", entries: "" },
      breakWebBlocker: { enabled: false, type: "deny", entries: "" },
      sessionAppBlocker: { enabled: false, apps: [] },
      breakAppBlocker: { enabled: false, apps: [] },
      slackBlockerEnabled: false,
      slackTeams: [],
      menuShowDuration: true,
      menuShowCategory: true,
      menuShowTodayTotal: false,
      showDockIcon: true,
      keepWindowOnTop: false,
      keepWindowOnTopOnBreak: true,
      showOnAllSpaces: false,
      minimizeWhenStarted: false,
      showOnTimerEnd: true,
      windowTrackerEnabled: false,
      windowTrackers: [],
      theme: "system",
      language: "en",
      localShortcutsEnabled: true,
      globalShortcutsEnabled: false,
      appleScriptEnabled: true,
      urlSchemeEnabled: true,
      developerTodoPreview: true,
    },
    active: null,
    intentionDraft: "",
    categoryId: categories[0]!.id,
    selectedDate: today,
    notesOnly: false,
    reportFilter: "all",
    reportRange: "day",
    miniPlayerOpen: false,
    notices: [],
  };
}

export function dateKey(value: number | Date): string {
  const date = typeof value === "number" ? new Date(value) : value;
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function sameDay(timestamp: number, key: string): boolean {
  return dateKey(timestamp) === key;
}

export function startFocus(
  state: PomodoroState,
  now: number,
  intention = state.intentionDraft,
  categoryId = state.categoryId,
  minutes = state.settings.sessionMinutes,
): PomodoroState {
  const cleanIntention = intention.trim();
  const resolvedCategoryId = categoryId || state.categoryId;
  const resolvedMinutes = focusMinutesForProfile(cleanIntention, minutes);
  const totalSec = Math.max(60, Math.round(resolvedMinutes * 60));
  return {
    ...state,
    active: {
      mode: "focus",
      kind: "focus",
      intention: cleanIntention,
      categoryId: resolvedCategoryId,
      startAt: now,
      endAt: now + totalSec * 1000,
      totalSec,
      remainingSec: totalSec,
      pausesSec: 0,
      noticesSent: [],
      notes: "",
    },
    intentionDraft: cleanIntention,
    categoryId: resolvedCategoryId,
    notices: pushNotice(
      state,
      now,
      "Session started",
      profileStartDetail(state, cleanIntention, resolvedCategoryId, resolvedMinutes),
    ),
  };
}

export function startBreak(
  state: PomodoroState,
  now: number,
  minutes = nextBreakMinutes(state),
): PomodoroState {
  const totalSec = Math.max(60, Math.round(minutes * 60));
  return {
    ...state,
    active: {
      mode: "break",
      kind: "break",
      intention: "Break",
      categoryId: state.categoryId,
      startAt: now,
      endAt: now + totalSec * 1000,
      totalSec,
      remainingSec: totalSec,
      pausesSec: 0,
      noticesSent: [],
      notes: "",
    },
    notices: pushNotice(state, now, "Break started", `${minutes} min break timer started.`),
  };
}

export function pauseTimer(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active || active.mode !== "focus") return state;
  const remainingSec = remainingSeconds(active, now);
  return {
    ...state,
    active: { ...active, mode: "paused", pausedAt: now, remainingSec },
    notices: pushNotice(state, now, "Session paused", active.intention || "Focus timer paused."),
  };
}

export function resumeTimer(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active || active.mode !== "paused") return state;
  const pausedFor = active.pausedAt ? Math.max(0, Math.round((now - active.pausedAt) / 1000)) : 0;
  return {
    ...state,
    active: {
      ...active,
      mode: "focus",
      pausedAt: undefined,
      pausesSec: active.pausesSec + pausedFor,
      endAt: now + active.remainingSec * 1000,
    },
    notices: pushNotice(state, now, "Session resumed", active.intention || "Focus timer resumed."),
  };
}

export function finishTimer(
  state: PomodoroState,
  now: number,
  mood: Mood = state.settings.defaultMood,
  notes = state.active?.notes ?? "",
): PomodoroState {
  const active = state.active;
  if (!active) return state;
  const kind = activeKind(active);
  const durationSec =
    active.mode === "ended" ? active.totalSec : Math.max(0, active.totalSec - remainingSeconds(active, now));
  const log: PomodoroLog = {
    id: makeId("log", now),
    kind,
    intention: active.intention,
    categoryId: active.categoryId,
    startAt: active.startAt,
    endAt: now,
    durationSec: Math.max(1, durationSec),
    pausesSec: active.pausesSec,
    mood: kind === "focus" ? mood : undefined,
    notes: notes.trim() || undefined,
  };
  return {
    ...state,
    active: null,
    logs: [...state.logs, log],
    notices: pushNotice(state, now, kind === "focus" ? "Session saved" : "Break saved", log.intention),
  };
}

export function abandonTimer(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active) return state;
  const log: PomodoroLog = {
    id: makeId("abandoned", now),
    kind: activeKind(active),
    intention: active.intention,
    categoryId: active.categoryId,
    startAt: active.startAt,
    endAt: now,
    durationSec: Math.max(1, active.totalSec - remainingSeconds(active, now)),
    pausesSec: active.pausesSec,
    notes: active.notes || undefined,
    abandoned: true,
  };
  return {
    ...state,
    active: null,
    lastAbandoned: log,
    notices: pushNotice(state, now, "Session abandoned", "Undo is available until another abandon."),
  };
}

export function undoAbandon(state: PomodoroState, now: number): PomodoroState {
  if (!state.lastAbandoned) return state;
  return {
    ...state,
    logs: [...state.logs, { ...state.lastAbandoned, abandoned: false }],
    lastAbandoned: undefined,
    notices: pushNotice(state, now, "Undo action", "The abandoned timer was restored to the log."),
  };
}

export function adjustTimerMinutes(state: PomodoroState, now: number, deltaMinutes: number): PomodoroState {
  const active = state.active;
  if (!active || active.mode === "ended") return state;
  const deltaSec = deltaMinutes * 60;
  const nextRemaining = Math.max(60, remainingSeconds(active, now) + deltaSec);
  return {
    ...state,
    active: {
      ...active,
      totalSec: Math.max(60, active.totalSec + deltaSec),
      remainingSec: nextRemaining,
      endAt: active.mode === "paused" ? active.endAt : now + nextRemaining * 1000,
    },
    notices: pushNotice(
      state,
      now,
      deltaMinutes > 0 ? "Session timer incremented" : "Session timer decremented",
      `${Math.abs(deltaMinutes)} min adjustment applied.`,
    ),
  };
}

export function tickPomodoro(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active) return state;
  const notificationState = applyTimerNotificationRules(state, now);
  if (notificationState !== state) return notificationState;
  if (active.mode === "paused" || active.mode === "ended") return state;
  const remainingSec = remainingSeconds(active, now);
  if (remainingSec > 0) {
    return { ...state, active: { ...active, remainingSec } };
  }
  if (activeKind(active) === "focus" && state.settings.autoStartBreak) {
    const saved = finishTimer(state, active.endAt, state.settings.defaultMood, active.notes);
    return startBreak(saved, active.endAt + 1);
  }
  if (activeKind(active) === "break" && state.settings.autoStartFocus) {
    const saved = finishTimer(state, active.endAt);
    return startFocus(saved, active.endAt + 1, saved.intentionDraft, saved.categoryId, saved.settings.sessionMinutes);
  }
  return {
    ...state,
    active: { ...active, mode: "ended", remainingSec: 0 },
    notices: pushNotice(
      state,
      now,
      active.mode === "break" ? "Break ended" : "Session ended",
      timerEndedDetail(state, activeKind(active)),
    ),
  };
}

export function testNotificationProfile(
  state: PomodoroState,
  now: number,
  kind: "ending-soon" | "presence" | "overflow",
): PomodoroState {
  switch (kind) {
    case "ending-soon":
      return {
        ...state,
        notices: pushNotice(state, now, "Ending soon", `${state.settings.endingSoonMinutes} min remaining warning tested locally.`),
      };
    case "presence":
      return {
        ...state,
        notices: pushNotice(state, now, "Presence reminder", "Local reminder to confirm you are still focused."),
      };
    case "overflow":
      return {
        ...state,
        notices: pushNotice(state, now, "Overflow reminder", `${state.settings.overflowMinutes} min overflow threshold tested locally.`),
      };
  }
}

export function testSoundProfile(state: PomodoroState, now: number, slot: PomodoroSoundSlot): PomodoroState {
  const profile = soundProfile(state, slot);
  return {
    ...state,
    notices: pushNotice(state, now, "Sound preview", `${profile.label}: ${profile.name} at ${Math.round(profile.volume * 100)}%.`),
  };
}

export function runTimerEndMainAction(
  state: PomodoroState,
  now: number,
  mood: Mood = state.settings.defaultMood,
  notes = state.active?.notes ?? "",
): PomodoroState {
  const active = state.active;
  if (!active || active.mode !== "ended") return state;
  const kind = activeKind(active);
  if (kind === "break") {
    const saved = finishTimer(state, now);
    if (state.settings.breakMainAction === "start-session") {
      return startFocus(saved, now + 1, saved.intentionDraft, saved.categoryId, saved.settings.sessionMinutes);
    }
    return saved;
  }

  const saved = finishTimer(state, now, mood, notes);
  if (state.settings.sessionMainAction === "break") {
    return startBreak(saved, now + 1);
  }
  if (state.settings.sessionMainAction === "restart") {
    return startFocus(saved, now + 1, active.intention, active.categoryId, active.totalSec / 60);
  }
  return saved;
}

function nextBreakMinutes(state: PomodoroState): number {
  const totalFocusMinutes = totalFocusSeconds(state, state.selectedDate) / 60;
  if (totalFocusMinutes >= state.settings.longBreakAfterFocusMinutes) {
    return state.settings.longBreakMinutes;
  }
  return state.settings.shortBreakMinutes;
}

export function totalFocusSeconds(state: PomodoroState, key: string): number {
  return state.logs
    .filter((log) => !log.abandoned && log.kind === "focus" && sameDay(log.startAt, key))
    .reduce((sum, log) => sum + log.durationSec, 0);
}

export function totalBreakSeconds(state: PomodoroState, key: string): number {
  return state.logs
    .filter((log) => !log.abandoned && log.kind === "break" && sameDay(log.startAt, key))
    .reduce((sum, log) => sum + log.durationSec, 0);
}

export function logInReportRange(log: PomodoroLog, state: PomodoroState): boolean {
  const range = reportRangeBounds(state.selectedDate, state.reportRange ?? "day");
  return log.startAt >= range.start && log.startAt < range.end;
}

export function reportRangeLabel(state: PomodoroState): string {
  const selected = new Date(`${state.selectedDate}T12:00:00`);
  switch (state.reportRange ?? "day") {
    case "day":
      return selected.toLocaleDateString(undefined, { month: "short", day: "numeric" });
    case "week": {
      const range = reportRangeBounds(state.selectedDate, "week");
      const start = new Date(range.start);
      const end = new Date(range.end - 1);
      return `${start.toLocaleDateString(undefined, { month: "short", day: "numeric" })} - ${end.toLocaleDateString(undefined, { month: "short", day: "numeric" })}`;
    }
    case "month":
      return selected.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  }
}

export function formatClock(sec: number): string {
  const safe = Math.max(0, Math.round(sec));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  return `${minutes}:${`${seconds}`.padStart(2, "0")}`;
}

export function formatDuration(sec: number): string {
  const minutes = Math.floor(sec / 60);
  const seconds = sec % 60;
  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return `${hours}h ${rest}m`;
  }
  if (minutes > 0) return `${minutes}m`;
  return `${seconds}s`;
}

export function parsePlainTasks(text: string, categoryId: string): PomodoroTask[] {
  return text
    .split(/\r?\n/)
    .map((line) => line.replace(/^[-*]\s+/, "").trim())
    .filter(Boolean)
    .map((title, index) => ({
      id: makeId("task", Date.now() + index),
      title,
      source: "plain-text" as const,
      categoryId,
      estimateMinutes: 25,
      done: false,
    }));
}

export function updateTaskEstimate(state: PomodoroState, id: string, estimateMinutes: number): PomodoroState {
  const nextEstimate = Math.max(1, Math.round(estimateMinutes));
  return {
    ...state,
    tasks: state.tasks.map((task) => (task.id === id ? { ...task, estimateMinutes: nextEstimate } : task)),
  };
}

export function scheduledItemsForDate(state: PomodoroState, key: string): PomodoroScheduleItem[] {
  return [...(state.schedules ?? [])]
    .filter((item) => item.dateKey === key)
    .sort((a, b) => a.startMinutes - b.startMinutes);
}

export function formatScheduleTime(startMinutes: number): string {
  const safe = Math.max(0, Math.min(23 * 60 + 59, Math.round(startMinutes)));
  const hours = Math.floor(safe / 60);
  const minutes = safe % 60;
  return `${`${hours}`.padStart(2, "0")}:${`${minutes}`.padStart(2, "0")}`;
}

export function addScheduleItem(
  state: PomodoroState,
  now: number,
  title: string,
  categoryId = state.categoryId,
  startTime = "09:00",
  durationMinutes = state.settings.sessionMinutes,
  source: PomodoroScheduleItem["source"] = "manual",
): PomodoroState {
  const cleanTitle = title.trim();
  const startMinutes = parseScheduleTime(startTime);
  if (!cleanTitle || startMinutes === null) {
    return {
      ...state,
      schedules: state.schedules ?? [],
      notices: pushNotice(state, now, "Calendar plan", "Title and valid start time are required."),
    };
  }
  const item: PomodoroScheduleItem = {
    id: makeId("schedule", now),
    title: cleanTitle,
    categoryId: categoryId || state.categoryId,
    dateKey: state.selectedDate,
    startMinutes,
    durationMinutes: Math.max(1, Math.round(durationMinutes)),
    source,
  };
  return {
    ...state,
    schedules: [...(state.schedules ?? []), item],
    notices: pushNotice(state, now, "Calendar plan", `${cleanTitle} scheduled at ${formatScheduleTime(startMinutes)}.`),
  };
}

export function removeScheduleItem(state: PomodoroState, now: number, id: string): PomodoroState {
  return {
    ...state,
    schedules: (state.schedules ?? []).filter((item) => item.id !== id),
    notices: pushNotice(state, now, "Calendar plan", "Scheduled block removed."),
  };
}

export function startScheduleItem(state: PomodoroState, now: number, id: string): PomodoroState {
  const item = (state.schedules ?? []).find((schedule) => schedule.id === id);
  if (!item) {
    return {
      ...state,
      schedules: state.schedules ?? [],
      notices: pushNotice(state, now, "Calendar plan", "Scheduled block was not found."),
    };
  }
  const withStarted = {
    ...state,
    schedules: (state.schedules ?? []).map((schedule) => (schedule.id === id ? { ...schedule, started: true } : schedule)),
  };
  const started = startFocus(withStarted, now, item.title, item.categoryId, item.durationMinutes);
  return {
    ...started,
    notices: pushNotice(started, now + 1, "Calendar plan", `Started scheduled block at ${formatScheduleTime(item.startMinutes)}.`),
  };
}

export function exportLogsCsv(state: PomodoroState): string {
  const rows = [
    ["type", "intention", "category", "start", "end", "duration_seconds", "pause_seconds", "mood", "notes"],
    ...state.logs.map((log) => [
      log.kind,
      log.intention,
      state.categories.find((cat) => cat.id === log.categoryId)?.name ?? log.categoryId,
      new Date(log.startAt).toISOString(),
      new Date(log.endAt).toISOString(),
      `${log.durationSec}`,
      `${log.pausesSec}`,
      log.mood ?? "",
      log.notes ?? "",
    ]),
  ];
  return rows.map((row) => row.map(csvCell).join(",")).join("\n");
}

export function currentBlockers(state: PomodoroState): string[] {
  const active = state.active;
  const mode = active?.mode;
  if (!mode || mode === "idle" || mode === "paused" || mode === "ended") return [];
  if (mode === "focus" && intentionHas(active.intention, "learn")) return [];
  const webRule = mode === "break" ? state.settings.breakWebBlocker : state.settings.sessionWebBlocker;
  const appRule = mode === "break" ? state.settings.breakAppBlocker : state.settings.sessionAppBlocker;
  const webEntries = webRule.enabled
    ? webRule.entries.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
    : [];
  const appEntries = appRule.enabled ? appRule.apps : [];
  const slackEntries = state.settings.slackBlockerEnabled ? state.settings.slackTeams.map((team) => `Slack: ${team}`) : [];
  return [...webEntries.map((entry) => `Web: ${entry}`), ...appEntries.map((entry) => `App: ${entry}`), ...slackEntries];
}

export function addWindowTrackerRule(
  state: PomodoroState,
  now: number,
  appName: string,
  windowTitle: string,
  categoryId = state.categoryId,
  intention = state.intentionDraft,
): PomodoroState {
  const cleanApp = appName.trim();
  const cleanWindow = windowTitle.trim();
  const cleanIntention = intention.trim();
  if (!cleanApp || !cleanWindow || !cleanIntention) {
    return {
      ...state,
      notices: pushNotice(state, now, "Window tracker", "App, window keyword and intention are required."),
    };
  }
  const rule: WindowTrackerRule = {
    id: makeId("tracker", now),
    appName: cleanApp,
    windowTitle: cleanWindow,
    categoryId,
    intention: cleanIntention,
  };
  return {
    ...state,
    settings: {
      ...state.settings,
      windowTrackerEnabled: true,
      windowTrackers: [...state.settings.windowTrackers, rule],
    },
    notices: pushNotice(state, now, "Window tracker", `Rule added for ${cleanApp}.`),
  };
}

export function removeWindowTrackerRule(state: PomodoroState, now: number, id: string): PomodoroState {
  return {
    ...state,
    settings: {
      ...state.settings,
      windowTrackers: state.settings.windowTrackers.filter((rule) => rule.id !== id),
    },
    notices: pushNotice(state, now, "Window tracker", "Rule removed."),
  };
}

export function testWindowTracker(
  state: PomodoroState,
  now: number,
  appName: string,
  windowTitle: string,
): PomodoroState {
  if (!state.settings.windowTrackerEnabled) {
    return {
      ...state,
      notices: pushNotice(state, now, "Window tracker", "Window tracker is disabled."),
    };
  }
  const match = state.settings.windowTrackers.find((rule) => {
    return includesFolded(appName, rule.appName) && includesFolded(windowTitle, rule.windowTitle);
  });
  if (!match) {
    return {
      ...state,
      notices: pushNotice(state, now, "Window tracker", "No local rule matched the supplied app/window."),
    };
  }
  if (state.settings.autoStartSuggestion) {
    const started = startFocus(state, now, match.intention, match.categoryId, state.settings.sessionMinutes);
    return {
      ...started,
      notices: pushNotice(started, now + 1, "Window tracker", `Matched ${match.appName}: ${match.intention}`),
    };
  }
  return {
    ...state,
    intentionDraft: match.intention,
    categoryId: match.categoryId,
    notices: pushNotice(state, now, "Window tracker", `Matched ${match.appName}: ${match.intention}`),
  };
}

export function runPomodoroShortcut(
  state: PomodoroState,
  shortcut: PomodoroShortcut,
  now: number,
  intention = state.intentionDraft,
): PomodoroState {
  switch (shortcut) {
    case "Start recent focus": {
      const recent = [...state.logs].reverse().find((log) => log.kind === "focus" && !log.abandoned);
      return startFocus(
        state,
        now,
        recent?.intention || intention || state.intentionDraft,
        recent?.categoryId || state.categoryId,
        recent ? Math.max(1, Math.round(recent.durationSec / 60)) : state.settings.sessionMinutes,
      );
    }
    case "Start focus":
      return startFocus(state, now, intention || state.intentionDraft, state.categoryId, state.settings.sessionMinutes);
    case "Pause / unpause":
      if (state.active?.mode === "paused") return resumeTimer(state, now);
      return pauseTimer(state, now);
    case "Take a break": {
      const saved = state.active?.mode === "focus" ? finishTimer(state, now) : state;
      return saved.active?.mode === "break" ? saved : startBreak(saved, now + 1);
    }
    case "Finish Session":
      return finishTimer(state, now);
    case "Abandon Session":
      return abandonTimer(state, now);
    case "Update intention": {
      const nextIntention = intention.trim();
      if (!nextIntention) {
        return {
          ...state,
          notices: pushNotice(state, now, "Shortcut action", "No intention supplied."),
        };
      }
      return {
        ...state,
        intentionDraft: nextIntention,
        active: state.active ? { ...state.active, intention: nextIntention } : state.active,
        notices: pushNotice(state, now, "Shortcut action", `Intention updated to ${nextIntention}.`),
      };
    }
    case "Current status":
      return {
        ...state,
        notices: pushNotice(
          state,
          now,
          "Shortcut action",
          `${state.active?.mode ?? "idle"} / ${state.active?.intention || state.intentionDraft || "No active timer"}`,
        ),
      };
  }
}

export function runPomodoroUrlCommand(
  state: PomodoroState,
  command: PomodoroUrlCommand,
  now: number,
  intention = state.intentionDraft,
  categoryId = state.categoryId,
): PomodoroState {
  switch (command) {
    case "start":
      return startFocus(state, now, intention || state.intentionDraft, categoryId || state.categoryId, state.settings.sessionMinutes);
    case "pause":
      return runPomodoroShortcut(state, "Pause / unpause", now, intention);
    case "finish":
      return finishTimer(state, now);
    case "break":
      return runPomodoroShortcut(state, "Take a break", now, intention);
    case "abandon":
      return abandonTimer(state, now);
    case "status":
      return runPomodoroShortcut(state, "Current status", now, intention);
  }
}

function remainingSeconds(active: PomodoroActiveTimer, now: number): number {
  if (active.mode === "paused") return active.remainingSec;
  return Math.max(0, Math.ceil((active.endAt - now) / 1000));
}

function applyTimerNotificationRules(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active) return state;
  const kind = activeKind(active);
  const sent = active.noticesSent ?? [];

  if (active.mode === "focus" && state.settings.endingSoonEnabled) {
    const remainingSec = remainingSeconds(active, now);
    const threshold = Math.max(1, state.settings.endingSoonMinutes) * 60;
    if (remainingSec > 0 && remainingSec <= threshold && !sent.includes("ending-soon")) {
      return markTimerNotice(state, active, now, "ending-soon", "Ending soon", `${formatDuration(remainingSec)} remaining.`);
    }
  }

  if (active.mode === "focus" && state.settings.presenceEnabled) {
    const elapsedSec = Math.max(0, Math.round((now - active.startAt) / 1000));
    const threshold = Math.max(60, Math.round(active.totalSec / 2));
    if (elapsedSec >= threshold && !sent.includes("presence")) {
      return markTimerNotice(state, active, now, "presence", "Presence reminder", active.intention || "Still focused?");
    }
  }

  if (active.mode === "paused" && state.settings.pauseOverflowEnabled && active.pausedAt) {
    const pausedSec = Math.max(0, Math.round((now - active.pausedAt) / 1000));
    const threshold = Math.max(1, state.settings.overflowMinutes) * 60;
    if (pausedSec >= threshold && !sent.includes("pause-overflow")) {
      return markTimerNotice(state, active, now, "pause-overflow", "Pause overflow", `${formatDuration(pausedSec)} paused.`);
    }
  }

  if (active.mode === "ended") {
    const threshold = Math.max(1, state.settings.overflowMinutes) * 60;
    const endedSec = Math.max(0, Math.round((now - active.endAt) / 1000));
    const enabled = kind === "break" ? state.settings.breakOverflowEnabled : state.settings.sessionOverflowEnabled;
    if (enabled && endedSec >= threshold && !sent.includes(`${kind}-overflow`)) {
      return markTimerNotice(state, active, now, `${kind}-overflow`, kind === "break" ? "Break overflow" : "Session overflow", `${formatDuration(endedSec)} past timer end.`);
    }
  }

  return state;
}

function markTimerNotice(
  state: PomodoroState,
  active: PomodoroActiveTimer,
  now: number,
  key: string,
  title: string,
  detail: string,
): PomodoroState {
  return {
    ...state,
    active: { ...active, noticesSent: [...(active.noticesSent ?? []), key] },
    notices: pushNotice(state, now, title, detail),
  };
}

function activeKind(active: PomodoroActiveTimer): "focus" | "break" {
  return active.kind ?? (active.mode === "break" ? "break" : "focus");
}

function focusMinutesForProfile(intention: string, minutes: number): number {
  if (intentionHas(intention, "reading")) return 30;
  return minutes;
}

function profileStartDetail(state: PomodoroState, intention: string, categoryId: string, minutes: number): string {
  const details = [intention || "Focus timer started."];
  if (intentionHas(intention, "reading")) details.push("Profile rule: reading uses 30 min focus.");
  if (intentionHas(intention, "learn")) details.push("Profile rule: learn disables blockers.");
  const category = state.categories.find((cat) => cat.id === categoryId);
  if (category?.name.toLowerCase() === "meeting") details.push("Profile rule: Meeting silences ending notifications.");
  if (minutes !== state.settings.sessionMinutes) details.push(`${minutes} min`);
  return details.join(" ");
}

function timerEndedDetail(state: PomodoroState, kind: "focus" | "break"): string {
  const base = kind === "break" ? "Log the break or start a new focus." : "Write notes, save, or take a break.";
  const profile = soundProfile(state, kind === "break" ? "break-end" : "session-end");
  return `${base} End sound: ${profile.name} at ${Math.round(profile.volume * 100)}%.`;
}

function soundProfile(state: PomodoroState, slot: PomodoroSoundSlot): { label: string; name: string; volume: number } {
  switch (slot) {
    case "session":
      return { label: "Session sound", name: state.settings.sessionSound, volume: state.settings.sessionVolume };
    case "session-end":
      return { label: "Session end sound", name: state.settings.sessionEndSound, volume: state.settings.sessionEndVolume };
    case "break":
      return { label: "Break sound", name: state.settings.breakSound, volume: state.settings.breakVolume };
    case "break-end":
      return { label: "Break end sound", name: state.settings.breakEndSound, volume: state.settings.breakEndVolume };
  }
}

function intentionHas(intention: string, needle: string): boolean {
  return intention.toLowerCase().includes(needle.toLowerCase());
}

function parseScheduleTime(value: string): number | null {
  const match = value.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
    return null;
  }
  return hours * 60 + minutes;
}

function reportRangeBounds(selectedDate: string, range: PomodoroReportRange): { start: number; end: number } {
  const selected = new Date(`${selectedDate}T00:00:00`);
  if (range === "month") {
    const start = new Date(selected.getFullYear(), selected.getMonth(), 1);
    const end = new Date(selected.getFullYear(), selected.getMonth() + 1, 1);
    return { start: start.getTime(), end: end.getTime() };
  }
  if (range === "week") {
    const start = new Date(selected);
    const day = start.getDay();
    const offset = day === 0 ? -6 : 1 - day;
    start.setDate(start.getDate() + offset);
    const end = new Date(start);
    end.setDate(start.getDate() + 7);
    return { start: start.getTime(), end: end.getTime() };
  }
  const end = new Date(selected);
  end.setDate(selected.getDate() + 1);
  return { start: selected.getTime(), end: end.getTime() };
}

function includesFolded(value: string, expected: string): boolean {
  return value.toLowerCase().includes(expected.toLowerCase());
}

function pushNotice(state: PomodoroState, at: number, title: string, detail: string): PomodoroNotice[] {
  return [{ id: makeId("notice", at), at, title, detail }, ...state.notices].slice(0, 8);
}

function makeId(prefix: string, now: number): string {
  return `${prefix}-${Math.round(now).toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function csvCell(value: string): string {
  const escaped = value.replace(/"/g, '""');
  return /[",\n]/.test(escaped) ? `"${escaped}"` : escaped;
}
