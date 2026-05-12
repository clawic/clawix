export type TimerMode = "idle" | "focus" | "paused" | "break" | "ended";

export type Mood = "focused" | "neutral" | "distracted";

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

export interface AppBlockerRule {
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

export interface WindowTrackerRule {
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

export interface PomodoroActiveTimer {
  mode: TimerMode;
  intention: string;
  categoryId: string;
  startAt: number;
  endAt: number;
  totalSec: number;
  remainingSec: number;
  pausesSec: number;
  pausedAt?: number;
  notes: string;
}

export interface PomodoroNotice {
  id: string;
  at: number;
  title: string;
  detail: string;
}

export interface PomodoroState {
  categories: PomodoroCategory[];
  tasks: PomodoroTask[];
  logs: PomodoroLog[];
  settings: PomodoroSettings;
  active: PomodoroActiveTimer | null;
  intentionDraft: string;
  categoryId: string;
  selectedDate: string;
  notesOnly: boolean;
  reportFilter: "all" | "focus" | "break" | "notes";
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
  const totalSec = Math.max(60, Math.round(minutes * 60));
  const cleanIntention = intention.trim();
  return {
    ...state,
    active: {
      mode: "focus",
      intention: cleanIntention,
      categoryId,
      startAt: now,
      endAt: now + totalSec * 1000,
      totalSec,
      remainingSec: totalSec,
      pausesSec: 0,
      notes: "",
    },
    intentionDraft: cleanIntention,
    categoryId,
    notices: pushNotice(state, now, "Session started", cleanIntention || "Focus timer started."),
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
      intention: "Break",
      categoryId: state.categoryId,
      startAt: now,
      endAt: now + totalSec * 1000,
      totalSec,
      remainingSec: totalSec,
      pausesSec: 0,
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
  const kind = active.mode === "break" ? "break" : "focus";
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
    kind: active.mode === "break" ? "break" : "focus",
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
  if (!active || active.mode === "paused" || active.mode === "ended") return state;
  const remainingSec = remainingSeconds(active, now);
  if (remainingSec > 0) {
    return { ...state, active: { ...active, remainingSec } };
  }
  return {
    ...state,
    active: { ...active, mode: "ended", remainingSec: 0 },
    notices: pushNotice(
      state,
      now,
      active.mode === "break" ? "Break ended" : "Session ended",
      active.mode === "break" ? "Log the break or start a new focus." : "Write notes, save, or take a break.",
    ),
  };
}

export function nextBreakMinutes(state: PomodoroState): number {
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
  const mode = state.active?.mode;
  if (!mode || mode === "idle" || mode === "paused" || mode === "ended") return [];
  const webRule = mode === "break" ? state.settings.breakWebBlocker : state.settings.sessionWebBlocker;
  const appRule = mode === "break" ? state.settings.breakAppBlocker : state.settings.sessionAppBlocker;
  const webEntries = webRule.enabled
    ? webRule.entries.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
    : [];
  const appEntries = appRule.enabled ? appRule.apps : [];
  const slackEntries = state.settings.slackBlockerEnabled ? state.settings.slackTeams.map((team) => `Slack: ${team}`) : [];
  return [...webEntries.map((entry) => `Web: ${entry}`), ...appEntries.map((entry) => `App: ${entry}`), ...slackEntries];
}

function remainingSeconds(active: PomodoroActiveTimer, now: number): number {
  if (active.mode === "paused") return active.remainingSec;
  return Math.max(0, Math.ceil((active.endAt - now) / 1000));
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
