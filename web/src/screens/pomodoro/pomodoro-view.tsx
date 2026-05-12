import { useEffect, useMemo, useReducer, useRef, useState } from "react";
import {
  abandonTimer,
  addWindowTrackerRule,
  adjustTimerMinutes,
  currentBlockers,
  dateKey,
  defaultPomodoroState,
  exportLogsCsv,
  finishTimer,
  formatClock,
  formatDuration,
  parsePlainTasks,
  pauseTimer,
  resumeTimer,
  removeWindowTrackerRule,
  runPomodoroShortcut,
  runPomodoroUrlCommand,
  sameDay,
  startBreak,
  startFocus,
  testNotificationProfile,
  testSoundProfile,
  testWindowTracker,
  tickPomodoro,
  totalBreakSeconds,
  totalFocusSeconds,
  undoAbandon,
  type BlockerRule,
  type Mood,
  type PomodoroCategory,
  type PomodoroLog,
  type PomodoroSettings,
  type PomodoroShortcut,
  type PomodoroSoundSlot,
  type PomodoroState,
  type PomodoroTask,
  type PomodoroUrlCommand,
} from "./pomodoro-model";
import { storage } from "../../lib/storage";
import cx from "../../lib/cx";
import {
  ArrowLeftIcon,
  ArrowRightIcon,
  BracesIcon,
  CalendarIcon,
  CheckIcon,
  ClockIcon,
  DownloadIcon,
  EllipsisIcon,
  ListChecksIcon,
  LockIcon,
  Maximize2Icon,
  MinusIcon,
  PauseIcon,
  PlayIcon,
  PlusIcon,
  RefreshCwIcon,
  SettingsIcon,
  TrashIcon,
  Undo2Icon,
  XIcon,
  ZapIcon,
} from "../../icons";

type Panel =
  | "timer"
  | "analytics"
  | "tasks"
  | "categories"
  | "profiles"
  | "blockers"
  | "calendar"
  | "automation"
  | "settings";

type Action =
  | { type: "replace"; state: PomodoroState }
  | { type: "tick"; now: number }
  | { type: "set-intention"; value: string }
  | { type: "set-category"; id: string }
  | { type: "start"; now: number; intention?: string; categoryId?: string; minutes?: number }
  | { type: "pause"; now: number }
  | { type: "resume"; now: number }
  | { type: "finish"; now: number; mood?: Mood; notes?: string }
  | { type: "break"; now: number; minutes?: number }
  | { type: "abandon"; now: number }
  | { type: "undo"; now: number }
  | { type: "adjust"; now: number; delta: number }
  | { type: "settings"; patch: Partial<PomodoroSettings> }
  | { type: "category-add"; name: string }
  | { type: "category-update"; category: PomodoroCategory }
  | { type: "category-archive"; id: string }
  | { type: "task-add"; title: string; source?: PomodoroTask["source"] }
  | { type: "tasks-import"; text: string }
  | { type: "task-toggle"; id: string }
  | { type: "task-delete"; id: string }
  | { type: "task-start"; task: PomodoroTask; now: number }
  | { type: "note"; value: string }
  | { type: "selected-date"; value: string }
  | { type: "notes-only"; value: boolean }
  | { type: "report-filter"; value: PomodoroState["reportFilter"] }
  | { type: "mini"; value: boolean }
  | { type: "notice"; now: number; title: string; detail: string }
  | { type: "shortcut"; shortcut: PomodoroShortcut; now: number; intention?: string }
  | { type: "url-command"; command: PomodoroUrlCommand; now: number; intention?: string; categoryId?: string }
  | { type: "tracker-add"; now: number; appName: string; windowTitle: string; categoryId: string; intention: string }
  | { type: "tracker-delete"; now: number; id: string }
  | { type: "tracker-test"; now: number; appName: string; windowTitle: string }
  | { type: "notification-test"; now: number; kind: "ending-soon" | "presence" | "overflow" }
  | { type: "sound-test"; now: number; slot: PomodoroSoundSlot };

const STORE_KEY = "pomodoro.sessionParity.v1";
const COLORS = ["#ef5b5b", "#73a6ff", "#f1b85b", "#8bd196", "#c89cff", "#e98fb1", "#7ed7d1"];
const SOUND_OPTIONS = ["Clock Ticking", "Ocean Waves", "Rain", "Brown Noise", "Kitchen Timer", "Gong", "None"];

function soundFrequency(name: string): number {
  switch (name) {
    case "Ocean Waves":
      return 180;
    case "Rain":
      return 320;
    case "Brown Noise":
      return 90;
    case "Kitchen Timer":
      return 1040;
    case "Gong":
      return 220;
    case "Clock Ticking":
    default:
      return 880;
  }
}

function soundWaveType(name: string): OscillatorType {
  switch (name) {
    case "Ocean Waves":
    case "Gong":
      return "sine";
    case "Brown Noise":
      return "sawtooth";
    case "Rain":
      return "square";
    case "Clock Ticking":
    case "Kitchen Timer":
    default:
      return "triangle";
  }
}

function reducer(state: PomodoroState, action: Action): PomodoroState {
  switch (action.type) {
    case "replace":
      return action.state;
    case "tick":
      return tickPomodoro(state, action.now);
    case "set-intention":
      return { ...state, intentionDraft: action.value };
    case "set-category":
      return { ...state, categoryId: action.id };
    case "start":
      return startFocus(state, action.now, action.intention, action.categoryId, action.minutes);
    case "pause":
      return pauseTimer(state, action.now);
    case "resume":
      return resumeTimer(state, action.now);
    case "finish":
      return finishTimer(state, action.now, action.mood, action.notes);
    case "break":
      return startBreak(state, action.now, action.minutes);
    case "abandon":
      return abandonTimer(state, action.now);
    case "undo":
      return undoAbandon(state, action.now);
    case "adjust":
      return adjustTimerMinutes(state, action.now, action.delta);
    case "settings":
      return { ...state, settings: { ...state.settings, ...action.patch } };
    case "category-add": {
      const name = action.name.trim();
      if (!name) return state;
      const category = {
        id: `cat-${Date.now().toString(36)}`,
        name,
        color: COLORS[state.categories.length % COLORS.length]!,
      };
      return { ...state, categories: [...state.categories, category], categoryId: category.id };
    }
    case "category-update":
      return {
        ...state,
        categories: state.categories.map((cat) => (cat.id === action.category.id ? action.category : cat)),
      };
    case "category-archive":
      return {
        ...state,
        categories: state.categories.map((cat) => (cat.id === action.id ? { ...cat, archived: true } : cat)),
      };
    case "task-add": {
      const title = action.title.trim();
      if (!title) return state;
      return {
        ...state,
        tasks: [
          ...state.tasks,
          {
            id: `task-${Date.now().toString(36)}`,
            title,
            source: action.source ?? "manual",
            categoryId: state.categoryId,
            estimateMinutes: state.settings.sessionMinutes,
            done: false,
          },
        ],
      };
    }
    case "tasks-import":
      return { ...state, tasks: [...state.tasks, ...parsePlainTasks(action.text, state.categoryId)] };
    case "task-toggle":
      return {
        ...state,
        tasks: state.tasks.map((task) => (task.id === action.id ? { ...task, done: !task.done } : task)),
      };
    case "task-delete":
      return { ...state, tasks: state.tasks.filter((task) => task.id !== action.id) };
    case "task-start":
      return startFocus(state, action.now, action.task.title, action.task.categoryId, action.task.estimateMinutes);
    case "note":
      return state.active ? { ...state, active: { ...state.active, notes: action.value } } : state;
    case "selected-date":
      return { ...state, selectedDate: action.value };
    case "notes-only":
      return { ...state, notesOnly: action.value };
    case "report-filter":
      return { ...state, reportFilter: action.value };
    case "mini":
      return { ...state, miniPlayerOpen: action.value };
    case "notice":
      return {
        ...state,
        notices: [{ id: `notice-${action.now}`, at: action.now, title: action.title, detail: action.detail }, ...state.notices].slice(0, 8),
      };
    case "shortcut":
      return runPomodoroShortcut(state, action.shortcut, action.now, action.intention);
    case "url-command":
      return runPomodoroUrlCommand(state, action.command, action.now, action.intention, action.categoryId);
    case "tracker-add":
      return addWindowTrackerRule(state, action.now, action.appName, action.windowTitle, action.categoryId, action.intention);
    case "tracker-delete":
      return removeWindowTrackerRule(state, action.now, action.id);
    case "tracker-test":
      return testWindowTracker(state, action.now, action.appName, action.windowTitle);
    case "notification-test":
      return testNotificationProfile(state, action.now, action.kind);
    case "sound-test":
      return testSoundProfile(state, action.now, action.slot);
    default:
      return state;
  }
}

export function PomodoroView() {
  const [state, dispatch] = useReducer(reducer, undefined, () => {
    const saved = storage.get<PomodoroState>(STORE_KEY);
    return saved ?? defaultPomodoroState();
  });
  const [panel, setPanel] = useState<Panel>("timer");
  const [mood, setMood] = useState<Mood>(state.settings.defaultMood);
  const [reflection, setReflection] = useState("");
  const audioRef = useRef<AudioContext | null>(null);
  const urlCommandApplied = useRef(false);

  useEffect(() => {
    storage.set(STORE_KEY, state);
  }, [state]);

  useEffect(() => {
    const id = window.setInterval(() => dispatch({ type: "tick", now: Date.now() }), 1000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (urlCommandApplied.current) return;
    urlCommandApplied.current = true;
    const parsed = parseUrlCommand(window.location);
    if (parsed) dispatch({ type: "url-command", now: Date.now(), ...parsed });
  }, []);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target?.tagName === "INPUT" || target?.tagName === "TEXTAREA" || target?.tagName === "SELECT") return;
      if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
        event.preventDefault();
        if (state.active?.mode === "ended") dispatch({ type: "finish", now: Date.now(), mood, notes: reflection || state.active.notes });
        else if (!state.active) dispatch({ type: "start", now: Date.now() });
      }
      if (event.key === " " && state.active) {
        event.preventDefault();
        dispatch({ type: state.active.mode === "paused" ? "resume" : "pause", now: Date.now() });
      }
      if (event.key === "Escape" && state.miniPlayerOpen) dispatch({ type: "mini", value: false });
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [mood, reflection, state.active, state.miniPlayerOpen]);

  useEffect(() => {
    if (!state.settings.backgroundSoundEnabled || !state.active || state.active.mode === "paused" || state.active.mode === "ended") {
      audioRef.current?.close().catch(() => undefined);
      audioRef.current = null;
      return;
    }
    const ctx = new AudioContext();
    const gain = ctx.createGain();
    const osc = ctx.createOscillator();
    const soundName = state.active.mode === "break" ? state.settings.breakSound : state.settings.sessionSound;
    if (soundName === "None") {
      ctx.close().catch(() => undefined);
      return;
    }
    osc.type = soundWaveType(soundName);
    osc.frequency.value = soundFrequency(soundName);
    gain.gain.value = state.active.mode === "break" ? state.settings.breakVolume * 0.04 : state.settings.sessionVolume * 0.04;
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    audioRef.current = ctx;
    return () => {
      osc.stop();
      ctx.close().catch(() => undefined);
      audioRef.current = null;
    };
  }, [
    state.active?.mode,
    state.settings.backgroundSoundEnabled,
    state.settings.breakSound,
    state.settings.breakVolume,
    state.settings.sessionSound,
    state.settings.sessionVolume,
  ]);

  const activeCategory = state.categories.find((cat) => cat.id === state.categoryId) ?? state.categories[0]!;
  const visibleLogs = useMemo(() => filterLogs(state.logs, state), [state.logs, state.selectedDate, state.notesOnly, state.reportFilter]);
  const activeBlockers = currentBlockers(state);

  return (
    <div className="h-full min-h-0 bg-[var(--color-bg)] text-[var(--color-fg)]">
      <div className="h-full flex min-h-0">
        <aside className="w-[250px] shrink-0 border-r border-[var(--color-border)] bg-[rgba(255,255,255,0.02)] p-3 flex flex-col gap-2">
          <div className="px-2 py-2">
            <div className="text-[15px] font-bold">Pomodoro</div>
            <div className="text-[11.5px] text-[var(--color-fg-secondary)]">Session parity workspace</div>
          </div>
          <PanelButton panel="timer" current={panel} icon={<ClockIcon size={15} />} label="Timer" onClick={setPanel} />
          <PanelButton panel="analytics" current={panel} icon={<CalendarIcon size={15} />} label="Analytics" onClick={setPanel} />
          <PanelButton panel="tasks" current={panel} icon={<ListChecksIcon size={15} />} label="To Do" onClick={setPanel} />
          <PanelButton panel="categories" current={panel} icon={<CheckIcon size={15} />} label="Categories" onClick={setPanel} />
          <PanelButton panel="profiles" current={panel} icon={<SettingsIcon size={15} />} label="Profile settings" onClick={setPanel} />
          <PanelButton panel="blockers" current={panel} icon={<LockIcon size={15} />} label="Blockers" onClick={setPanel} />
          <PanelButton panel="calendar" current={panel} icon={<CalendarIcon size={15} />} label="Calendar" onClick={setPanel} />
          <PanelButton panel="automation" current={panel} icon={<BracesIcon size={15} />} label="Automation" onClick={setPanel} />
          <PanelButton panel="settings" current={panel} icon={<SettingsIcon size={15} />} label="Settings" onClick={setPanel} />
          <div className="mt-auto rounded-[8px] border border-[var(--color-border)] p-3 text-[11.5px] text-[var(--color-fg-secondary)]">
            <div className="text-[var(--color-fg)]">{formatClock(state.active?.remainingSec ?? state.settings.sessionMinutes * 60)}</div>
            <div className="mt-1 flex items-center gap-1.5">
              <span className="h-1.5 w-1.5 rounded-full" style={{ background: activeCategory.color }} />
              {activeCategory.name}
            </div>
          </div>
        </aside>

        <main className="min-w-0 flex-1 overflow-hidden">
          {panel === "timer" && (
            <TimerPanel
              state={state}
              dispatch={dispatch}
              mood={mood}
              setMood={setMood}
              reflection={reflection}
              setReflection={setReflection}
              activeBlockers={activeBlockers}
            />
          )}
          {panel === "analytics" && <AnalyticsPanel state={state} dispatch={dispatch} visibleLogs={visibleLogs} />}
          {panel === "tasks" && <TasksPanel state={state} dispatch={dispatch} />}
          {panel === "categories" && <CategoriesPanel state={state} dispatch={dispatch} />}
          {panel === "profiles" && <ProfilesPanel state={state} dispatch={dispatch} />}
          {panel === "blockers" && <BlockersPanel state={state} dispatch={dispatch} activeBlockers={activeBlockers} />}
          {panel === "calendar" && <CalendarPanel state={state} dispatch={dispatch} />}
          {panel === "automation" && <AutomationPanel state={state} dispatch={dispatch} />}
          {panel === "settings" && <SettingsPanel state={state} dispatch={dispatch} />}
        </main>
      </div>

      {state.miniPlayerOpen && (
        <div className="fixed right-5 top-5 z-50 w-[290px] rounded-[12px] border border-[var(--color-popup-stroke)] menu-backdrop shadow-[var(--shadow-menu)] p-4">
          <div className="flex items-center justify-between">
            <div className="text-[12px] text-[var(--color-fg-secondary)]">Mini Player</div>
            <button className="icon-btn" onClick={() => dispatch({ type: "mini", value: false })} aria-label="Close mini player">
              <XIcon size={14} />
            </button>
          </div>
          <div className="mt-3 text-[30px] font-bold tabular-nums">{formatClock(state.active?.remainingSec ?? 0)}</div>
          <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">{state.active?.intention || "No active timer"}</div>
          <div className="mt-4 flex gap-2">
            <ActionButton icon={<MinusIcon size={14} />} label="-5" onClick={() => dispatch({ type: "adjust", now: Date.now(), delta: -5 })} />
            <ActionButton
              icon={state.active?.mode === "paused" ? <PlayIcon size={14} /> : <PauseIcon size={14} />}
              label={state.active?.mode === "paused" ? "Resume" : "Pause"}
              onClick={() => dispatch({ type: state.active?.mode === "paused" ? "resume" : "pause", now: Date.now() })}
            />
            <ActionButton icon={<PlusIcon size={14} />} label="+5" onClick={() => dispatch({ type: "adjust", now: Date.now(), delta: 5 })} />
          </div>
        </div>
      )}
    </div>
  );
}

function TimerPanel({
  state,
  dispatch,
  mood,
  setMood,
  reflection,
  setReflection,
  activeBlockers,
}: {
  state: PomodoroState;
  dispatch: React.Dispatch<Action>;
  mood: Mood;
  setMood: (mood: Mood) => void;
  reflection: string;
  setReflection: (value: string) => void;
  activeBlockers: string[];
}) {
  const active = state.active;
  const remaining = active?.remainingSec ?? state.settings.sessionMinutes * 60;
  const total = active?.totalSec ?? state.settings.sessionMinutes * 60;
  const progress = 1 - remaining / Math.max(1, total);
  const category = state.categories.find((cat) => cat.id === state.categoryId) ?? state.categories[0]!;

  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <div className="grid min-h-full grid-cols-[minmax(420px,0.95fr)_minmax(380px,1.05fr)] gap-6">
        <div className="flex min-h-[680px] flex-col items-center justify-center rounded-[14px] border border-[var(--color-border)] bg-[rgba(255,255,255,0.025)] p-6">
          <div className="mb-5 flex items-center gap-2">
            <input
              value={state.intentionDraft}
              onChange={(event) => dispatch({ type: "set-intention", value: event.target.value })}
              placeholder="What do you want to focus on?"
              className="h-10 w-[310px] rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] px-3 text-center text-[13px] outline-none"
            />
            <select
              value={state.categoryId}
              onChange={(event) => dispatch({ type: "set-category", id: event.target.value })}
              className="h-10 rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] px-2 text-[12px]"
            >
              {state.categories.filter((cat) => !cat.archived).map((cat) => (
                <option key={cat.id} value={cat.id}>{cat.name}</option>
              ))}
            </select>
          </div>

          <div className="relative grid h-[260px] w-[260px] place-items-center">
            <div
              className="absolute inset-0 rounded-full"
              style={{
                background: `conic-gradient(${category.color} ${progress * 360}deg, rgba(255,255,255,0.10) 0deg)`,
              }}
            />
            <div className="absolute inset-[30px] rounded-full bg-[var(--color-bg)]" />
            <div className="relative text-center">
              <div className="text-[46px] font-bold tabular-nums">{formatClock(remaining)}</div>
              <div className="mt-1 text-[12px] text-[var(--color-fg-secondary)]">{active?.mode ?? "idle"}</div>
            </div>
          </div>

          <input
            type="range"
            min={state.settings.snapIntervalMinutes}
            max={180}
            step={state.settings.snapIntervalMinutes}
            value={Math.round(total / 60)}
            disabled={!!active && active.mode !== "ended"}
            onChange={(event) => dispatch({ type: "settings", patch: { sessionMinutes: Number(event.target.value) } })}
            className="mt-6 w-[260px]"
          />
          <div className="mt-1 text-[12px] text-[var(--color-fg-secondary)]">
            {Math.round(total / 60)} min, snap {state.settings.snapIntervalMinutes} min
          </div>

          <div className="mt-8 flex flex-wrap justify-center gap-2">
            {!active && (
              <PrimaryButton icon={<PlayIcon size={15} />} label="Start Session" onClick={() => dispatch({ type: "start", now: Date.now() })} />
            )}
            {active?.mode === "focus" && (
              <>
                <ActionButton icon={<PauseIcon size={14} />} label="Pause" onClick={() => dispatch({ type: "pause", now: Date.now() })} />
                <PrimaryButton icon={<CheckIcon size={15} />} label="Finish" onClick={() => dispatch({ type: "finish", now: Date.now(), mood, notes: active.notes })} />
                <ActionButton
                  icon={<ZapIcon size={14} />}
                  label="Break"
                  onClick={() => {
                    const now = Date.now();
                    dispatch({ type: "finish", now, mood, notes: active.notes });
                    dispatch({ type: "break", now: now + 1 });
                  }}
                />
              </>
            )}
            {active?.mode === "paused" && (
              <PrimaryButton icon={<PlayIcon size={15} />} label="Resume" onClick={() => dispatch({ type: "resume", now: Date.now() })} />
            )}
            {active?.mode === "break" && (
              <PrimaryButton icon={<CheckIcon size={15} />} label="Save Break" onClick={() => dispatch({ type: "finish", now: Date.now() })} />
            )}
            {active?.mode === "ended" && (
              <>
                <PrimaryButton icon={<CheckIcon size={15} />} label="Save" onClick={() => dispatch({ type: "finish", now: Date.now(), mood, notes: reflection || active.notes })} />
                <ActionButton icon={<PlayIcon size={14} />} label="Take Break" onClick={() => dispatch({ type: "break", now: Date.now() })} />
                <ActionButton icon={<RefreshCwIcon size={14} />} label="Repeat" onClick={() => dispatch({ type: "start", now: Date.now(), intention: active.intention, categoryId: active.categoryId })} />
              </>
            )}
            {active && (
              <>
                <ActionButton icon={<MinusIcon size={14} />} label="-5 min" onClick={() => dispatch({ type: "adjust", now: Date.now(), delta: -5 })} />
                <ActionButton icon={<PlusIcon size={14} />} label="+5 min" onClick={() => dispatch({ type: "adjust", now: Date.now(), delta: 5 })} />
                <ActionButton icon={<TrashIcon size={14} />} label="Abandon" onClick={() => dispatch({ type: "abandon", now: Date.now() })} />
              </>
            )}
            <ActionButton icon={<Maximize2Icon size={14} />} label="Mini Player" onClick={() => dispatch({ type: "mini", value: true })} />
            {state.lastAbandoned && (
              <ActionButton icon={<Undo2Icon size={14} />} label="Undo abandon" onClick={() => dispatch({ type: "undo", now: Date.now() })} />
            )}
          </div>

          {active && (
            <textarea
              value={active.notes}
              onChange={(event) => dispatch({ type: "note", value: event.target.value })}
              placeholder="Write down your thoughts, learning, or distraction..."
              className="mt-6 min-h-[90px] w-full max-w-[440px] rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] p-3 text-[13px] outline-none"
            />
          )}

          {active?.mode === "ended" && (
            <div className="mt-4 w-full max-w-[440px] rounded-[8px] border border-[var(--color-border)] bg-[rgba(255,255,255,0.03)] p-3">
              <div className="mb-2 text-[12px] text-[var(--color-fg-secondary)]">Reflection mood</div>
              <div className="flex gap-2">
                {(["focused", "neutral", "distracted"] as Mood[]).map((m) => (
                  <button
                    key={m}
                    onClick={() => setMood(m)}
                    className={cx("h-8 rounded-[8px] px-3 text-[12px]", mood === m ? "bg-[var(--color-pastel-blue)] text-black" : "bg-[var(--color-card)]")}
                  >
                    {m}
                  </button>
                ))}
              </div>
              <textarea
                value={reflection}
                onChange={(event) => setReflection(event.target.value)}
                placeholder="What did you learn in this Session?"
                className="mt-3 min-h-[80px] w-full rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] p-3 text-[13px] outline-none"
              />
            </div>
          )}
        </div>

        <div className="flex min-h-[680px] flex-col gap-4">
          <DayHeader state={state} dispatch={dispatch} />
          <StatsGrid state={state} />
          <Card title="Active blockers" action={`${activeBlockers.length} active`}>
            {activeBlockers.length === 0 ? (
              <EmptyText>No website, app, or Slack blocker is active for this timer state.</EmptyText>
            ) : (
              <div className="flex flex-wrap gap-2">
                {activeBlockers.map((entry) => <span key={entry} className="chip">{entry}</span>)}
              </div>
            )}
          </Card>
          <Card title="Notices" action="In-app">
            <div className="space-y-2">
              {state.notices.map((notice) => (
                <div key={notice.id} className="rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
                  <div className="text-[12.5px]">{notice.title}</div>
                  <div className="text-[11.5px] text-[var(--color-fg-secondary)]">{notice.detail}</div>
                </div>
              ))}
              {state.notices.length === 0 && <EmptyText>Timer notifications, overflow tests, and shortcut actions appear here.</EmptyText>}
            </div>
          </Card>
          <Timeline state={state} />
        </div>
      </div>
    </section>
  );
}

function AnalyticsPanel({ state, dispatch, visibleLogs }: { state: PomodoroState; dispatch: React.Dispatch<Action>; visibleLogs: PomodoroLog[] }) {
  const csv = exportLogsCsv(state);
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-[18px] font-bold">Analytics</div>
          <div className="text-[12px] text-[var(--color-fg-secondary)]">Daily, weekly-style totals, category distribution, mood split, notes and exports.</div>
        </div>
        <div className="flex gap-2">
          <DownloadButton filename="session-export.csv" data={csv} label="CSV" mime="text/csv" />
          <DownloadButton filename="session-export.json" data={JSON.stringify(state.logs, null, 2)} label="JSON" mime="application/json" />
        </div>
      </div>
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <div className="space-y-4">
          <DayHeader state={state} dispatch={dispatch} />
          <StatsGrid state={state} />
          <Card title="Category distribution" action="Focus">
            <Distribution state={state} />
          </Card>
          <Card title="Mood" action="Reflection">
            <MoodDistribution logs={visibleLogs} />
          </Card>
        </div>
        <div className="space-y-4">
          <div className="flex items-center gap-2">
            <label className="flex items-center gap-2 text-[12px] text-[var(--color-fg-secondary)]">
              <input type="checkbox" checked={state.notesOnly} onChange={(event) => dispatch({ type: "notes-only", value: event.target.checked })} />
              Show notes only
            </label>
            <select
              value={state.reportFilter}
              onChange={(event) => dispatch({ type: "report-filter", value: event.target.value as PomodoroState["reportFilter"] })}
              className="h-8 rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] px-2 text-[12px]"
            >
              <option value="all">All</option>
              <option value="focus">Focus</option>
              <option value="break">Break</option>
              <option value="notes">Notes</option>
            </select>
          </div>
          <Card title="Timeline" action={`${visibleLogs.length} rows`}>
            <div className="space-y-2">
              {visibleLogs.map((log) => <LogRow key={log.id} log={log} state={state} />)}
              {visibleLogs.length === 0 && <EmptyText>No sessions match this day/filter.</EmptyText>}
            </div>
          </Card>
        </div>
      </div>
    </section>
  );
}

function TasksPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const [title, setTitle] = useState("");
  const [bulk, setBulk] = useState("");
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title="To Do" subtitle="Local equivalent of Session 3 To Do, Apple Reminders, Things, Linear and plain-text imports." />
      <div className="mt-5 grid grid-cols-[380px_1fr] gap-4">
        <Card title="Add task" action="Today">
          <div className="flex gap-2">
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Task title" className="field flex-1" />
            <PrimaryButton icon={<PlusIcon size={14} />} label="Add" onClick={() => { dispatch({ type: "task-add", title }); setTitle(""); }} />
          </div>
          <textarea value={bulk} onChange={(e) => setBulk(e.target.value)} placeholder="- Paste plain text tasks&#10;- One per line" className="field mt-3 min-h-[160px] w-full p-3" />
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton icon={<ListChecksIcon size={14} />} label="Import plain text" onClick={() => { dispatch({ type: "tasks-import", text: bulk }); setBulk(""); }} />
            <ActionButton icon={<ZapIcon size={14} />} label="Simulate Reminders sync" onClick={() => dispatch({ type: "task-add", title: "Reminder: review focus plan", source: "reminders" })} />
            <ActionButton icon={<ZapIcon size={14} />} label="Things import" onClick={() => dispatch({ type: "task-add", title: "Things: prepare focus list", source: "things" })} />
            <ActionButton icon={<ZapIcon size={14} />} label="Linear import" onClick={() => dispatch({ type: "task-add", title: "Linear: ship Pomodoro parity", source: "linear" })} />
          </div>
        </Card>
        <Card title="Today" action={`${state.tasks.filter((task) => !task.done).length} open`}>
          <div className="space-y-2">
            {state.tasks.map((task) => (
              <div key={task.id} className="flex items-center gap-3 rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
                <input type="checkbox" checked={task.done} onChange={() => dispatch({ type: "task-toggle", id: task.id })} />
                <div className="min-w-0 flex-1">
                  <div className={cx("truncate text-[13px]", task.done && "line-through text-[var(--color-fg-secondary)]")}>{task.title}</div>
                  <div className="text-[11.5px] text-[var(--color-fg-secondary)]">{task.source} / {task.estimateMinutes} min</div>
                </div>
                <ActionButton icon={<PlayIcon size={14} />} label="Start" onClick={() => dispatch({ type: "task-start", task, now: Date.now() })} />
                <button className="icon-btn" onClick={() => dispatch({ type: "task-delete", id: task.id })} aria-label="Delete task"><TrashIcon size={14} /></button>
              </div>
            ))}
            {state.tasks.length === 0 && <EmptyText>No tasks yet.</EmptyText>}
          </div>
        </Card>
      </div>
    </section>
  );
}

function CategoriesPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const [name, setName] = useState("");
  const [filter, setFilter] = useState("");
  const categories = state.categories.filter((cat) => cat.name.toLowerCase().includes(filter.toLowerCase()));
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title="Categories" subtitle="Create, filter, edit color, archive, and use category IDs for URL-scheme style starts." />
      <div className="mt-5 grid grid-cols-[360px_1fr] gap-4">
        <Card title="New category" action="Custom colors">
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Category name" className="field w-full" />
          <PrimaryButton className="mt-3" icon={<PlusIcon size={14} />} label="Add new category" onClick={() => { dispatch({ type: "category-add", name }); setName(""); }} />
          <input value={filter} onChange={(e) => setFilter(e.target.value)} placeholder="Filter categories" className="field mt-4 w-full" />
        </Card>
        <Card title="Active categories" action={`${categories.length} shown`}>
          <div className="space-y-2">
            {categories.map((cat) => (
              <div key={cat.id} className="flex items-center gap-3 rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
                <input type="color" value={cat.color} onChange={(e) => dispatch({ type: "category-update", category: { ...cat, color: e.target.value } })} />
                <input value={cat.name} onChange={(e) => dispatch({ type: "category-update", category: { ...cat, name: e.target.value } })} className="field flex-1" />
                <span className="font-mono text-[11px] text-[var(--color-fg-secondary)]">{cat.id}</span>
                <ActionButton icon={<TrashIcon size={14} />} label={cat.archived ? "Archived" : "Archive"} onClick={() => dispatch({ type: "category-archive", id: cat.id })} />
              </div>
            ))}
          </div>
        </Card>
      </div>
    </section>
  );
}

function ProfilesPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const settings = state.settings;
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title="Profile Settings" subtitle="Rules can tune duration, notifications, website blockers and app blockers by intention/category." />
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <Card title="Session" action="Default profile">
          <NumberRow label="Session duration (min)" value={settings.sessionMinutes} onChange={(v) => dispatch({ type: "settings", patch: { sessionMinutes: v } })} />
          <NumberRow label="Short break (min)" value={settings.shortBreakMinutes} onChange={(v) => dispatch({ type: "settings", patch: { shortBreakMinutes: v } })} />
          <NumberRow label="Long break (min)" value={settings.longBreakMinutes} onChange={(v) => dispatch({ type: "settings", patch: { longBreakMinutes: v } })} />
          <NumberRow label="Long break after focus (min)" value={settings.longBreakAfterFocusMinutes} onChange={(v) => dispatch({ type: "settings", patch: { longBreakAfterFocusMinutes: v } })} />
          <NumberRow label="Breaths before focus" value={settings.breathCount} onChange={(v) => dispatch({ type: "settings", patch: { breathCount: v } })} />
        </Card>
        <Card title="Notification profile" action="Overflow">
          <Toggle label="Ending soon notification" checked={settings.endingSoonEnabled} onChange={(v) => dispatch({ type: "settings", patch: { endingSoonEnabled: v } })} />
          <NumberRow label="Ending soon duration (min)" value={settings.endingSoonMinutes} onChange={(v) => dispatch({ type: "settings", patch: { endingSoonMinutes: v } })} />
          <Toggle label="Presence reminder" checked={settings.presenceEnabled} onChange={(v) => dispatch({ type: "settings", patch: { presenceEnabled: v } })} />
          <Toggle label="Session overflow" checked={settings.sessionOverflowEnabled} onChange={(v) => dispatch({ type: "settings", patch: { sessionOverflowEnabled: v } })} />
          <Toggle label="Pause overflow" checked={settings.pauseOverflowEnabled} onChange={(v) => dispatch({ type: "settings", patch: { pauseOverflowEnabled: v } })} />
          <Toggle label="Break overflow" checked={settings.breakOverflowEnabled} onChange={(v) => dispatch({ type: "settings", patch: { breakOverflowEnabled: v } })} />
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton icon={<ZapIcon size={14} />} label="Test ending soon" onClick={() => dispatch({ type: "notification-test", now: Date.now(), kind: "ending-soon" })} />
            <ActionButton icon={<ZapIcon size={14} />} label="Test presence" onClick={() => dispatch({ type: "notification-test", now: Date.now(), kind: "presence" })} />
            <ActionButton icon={<ZapIcon size={14} />} label="Test overflow" onClick={() => dispatch({ type: "notification-test", now: Date.now(), kind: "overflow" })} />
          </div>
        </Card>
      </div>
      <div className="mt-4">
        <Card title="Example rules" action="Local">
          <div className="grid grid-cols-2 gap-3 text-[12.5px] text-[var(--color-fg-secondary)]">
            <RuleText text='When intention contains "reading", use 30 min focus.' />
            <RuleText text="During break, block selected productivity apps." />
            <RuleText text='When intention contains "learn", disable blockers.' />
            <RuleText text='When category is "Meeting", silence ending notifications.' />
          </div>
        </Card>
      </div>
    </section>
  );
}

function BlockersPanel({ state, dispatch, activeBlockers }: { state: PomodoroState; dispatch: React.Dispatch<Action>; activeBlockers: string[] }) {
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title="Blockers" subtitle="Local, in-app equivalents for Session website, app and Slack blockers. No OS or browser permissions are changed." />
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <WebsiteBlockerCard title="Session website blocker" rule={state.settings.sessionWebBlocker} onChange={(rule) => dispatch({ type: "settings", patch: { sessionWebBlocker: rule } })} />
        <WebsiteBlockerCard title="Break website blocker" rule={state.settings.breakWebBlocker} onChange={(rule) => dispatch({ type: "settings", patch: { breakWebBlocker: rule } })} />
        <AppBlockerCard title="Session app blocker" enabled={state.settings.sessionAppBlocker.enabled} apps={state.settings.sessionAppBlocker.apps} onChange={(enabled, apps) => dispatch({ type: "settings", patch: { sessionAppBlocker: { enabled, apps } } })} />
        <AppBlockerCard title="Break app blocker" enabled={state.settings.breakAppBlocker.enabled} apps={state.settings.breakAppBlocker.apps} onChange={(enabled, apps) => dispatch({ type: "settings", patch: { breakAppBlocker: { enabled, apps } } })} />
        <Card title="Slack blocker" action="Teams">
          <Toggle label="Mute selected Slack teams" checked={state.settings.slackBlockerEnabled} onChange={(v) => dispatch({ type: "settings", patch: { slackBlockerEnabled: v } })} />
          <textarea value={state.settings.slackTeams.join("\n")} onChange={(e) => dispatch({ type: "settings", patch: { slackTeams: e.target.value.split(/\r?\n/).filter(Boolean) } })} className="field mt-3 min-h-[120px] w-full p-3" placeholder="Team name per line" />
        </Card>
        <Card title="Currently enforced in app" action={`${activeBlockers.length}`}>
          {activeBlockers.length ? activeBlockers.map((entry) => <div key={entry} className="chip mb-2">{entry}</div>) : <EmptyText>No active blocker for the current timer state.</EmptyText>}
        </Card>
      </div>
    </section>
  );
}

function CalendarPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title="Calendar" subtitle="Daily planning surface with scheduled tasks, logged Sessions, breaks and projected timer block." />
      <div className="mt-5 grid grid-cols-[380px_1fr] gap-4">
        <Card title="Calendar integration" action="Local">
          <Toggle label="Show calendar on Session" checked={true} onChange={() => undefined} />
          <Toggle label="Show Sessions on Apple calendar" checked={false} onChange={() => dispatch({ type: "notice", now: Date.now(), title: "Apple Calendar sync", detail: "External calendar write is disabled in this local example." })} />
          <Toggle label="Apple Reminder integration" checked={state.settings.developerTodoPreview} onChange={(v) => dispatch({ type: "settings", patch: { developerTodoPreview: v } })} />
          <NumberRow label="Default calendar duration (min)" value={state.settings.sessionMinutes} onChange={(v) => dispatch({ type: "settings", patch: { sessionMinutes: v } })} />
        </Card>
        <div className="space-y-4">
          <DayHeader state={state} dispatch={dispatch} />
          <Timeline state={state} large />
        </div>
      </div>
    </section>
  );
}

function AutomationPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const [trackerApp, setTrackerApp] = useState("Safari");
  const [trackerWindow, setTrackerWindow] = useState("Reading");
  const [trackerIntention, setTrackerIntention] = useState(state.intentionDraft || "Read reference");
  const [trackerCategory, setTrackerCategory] = useState(state.categoryId);
  const shortcuts: PomodoroShortcut[] = ["Start recent focus", "Start focus", "Pause / unpause", "Take a break", "Finish Session", "Abandon Session", "Update intention", "Current status"];
  const localUrlBase = `${window.location.origin}${window.location.pathname}?example=pomodoro`;
  const shortcutJson = JSON.stringify({
    state: state.active?.mode ?? "idle",
    title: state.active?.intention ?? state.intentionDraft,
    category: state.categories.find((cat) => cat.id === state.categoryId)?.name,
    remainingSecond: state.active?.remainingSec ?? 0,
    totalDurationSecond: state.active?.totalSec ?? state.settings.sessionMinutes * 60,
  }, null, 2);
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title="Automation" subtitle="Shortcuts, URL scheme, AppleScript and window tracker equivalents for this Pomodoro example." />
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <Card title="Shortcuts" action="Actions">
          {shortcuts.map((shortcut) => (
            <button
              key={shortcut}
              className="row-btn"
              onClick={() => dispatch({ type: "shortcut", shortcut, now: Date.now(), intention: state.intentionDraft })}
            >
              {shortcut}
            </button>
          ))}
        </Card>
        <Card title="Current Session JSON" action="Copy source">
          <pre className="max-h-[300px] overflow-auto rounded-[8px] bg-black p-3 text-[11px] text-[var(--color-fg-secondary)]">{shortcutJson}</pre>
        </Card>
        <Card title="URL scheme" action="session://">
          <CodeLine value={`session://start?intention=${encodeURIComponent(state.intentionDraft || "Focus")}&category=${state.categoryId}`} />
          <CodeLine value="session://pause" />
          <CodeLine value="session://finish" />
          <CodeLine value="session://break" />
          <div className="mt-3 text-[11.5px] text-[var(--color-fg-secondary)]">Local command URLs</div>
          <CodeLine value={`${localUrlBase}&session=start&intention=${encodeURIComponent(state.intentionDraft || "Focus")}&category=${state.categoryId}`} />
          <CodeLine value={`${localUrlBase}&session=pause`} />
          <CodeLine value={`${localUrlBase}&session=finish`} />
          <CodeLine value={`${localUrlBase}&session=break`} />
          <CodeLine value={`${localUrlBase}&session=status`} />
        </Card>
        <Card title="Window tracker" action={state.settings.windowTrackerEnabled ? "Enabled" : "Off"}>
          <Toggle label="Enable window tracker" checked={state.settings.windowTrackerEnabled} onChange={(v) => dispatch({ type: "settings", patch: { windowTrackerEnabled: v } })} />
          <div className="mt-3 grid grid-cols-2 gap-2">
            <input value={trackerApp} onChange={(e) => setTrackerApp(e.target.value)} className="field" placeholder="App name" />
            <input value={trackerWindow} onChange={(e) => setTrackerWindow(e.target.value)} className="field" placeholder="Window keyword" />
            <input value={trackerIntention} onChange={(e) => setTrackerIntention(e.target.value)} className="field" placeholder="Suggested intention" />
            <select value={trackerCategory} onChange={(e) => setTrackerCategory(e.target.value)} className="field">
              {state.categories.filter((cat) => !cat.archived).map((cat) => <option key={cat.id} value={cat.id}>{cat.name}</option>)}
            </select>
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton
              icon={<PlusIcon size={14} />}
              label="Add tracker rule"
              onClick={() => dispatch({ type: "tracker-add", now: Date.now(), appName: trackerApp, windowTitle: trackerWindow, categoryId: trackerCategory, intention: trackerIntention })}
            />
            <ActionButton
              icon={<ZapIcon size={14} />}
              label="Test tracker match"
              onClick={() => dispatch({ type: "tracker-test", now: Date.now(), appName: trackerApp, windowTitle: trackerWindow })}
            />
          </div>
          <div className="mt-3 space-y-2">
            {state.settings.windowTrackers.map((rule) => (
              <div key={rule.id} className="flex items-center gap-3 rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[12.5px]">{rule.appName} / {rule.windowTitle}</div>
                  <div className="text-[11.5px] text-[var(--color-fg-secondary)]">{rule.intention}</div>
                </div>
                <button className="icon-btn" onClick={() => dispatch({ type: "tracker-delete", now: Date.now(), id: rule.id })} aria-label="Delete tracker rule"><TrashIcon size={14} /></button>
              </div>
            ))}
            {state.settings.windowTrackers.length === 0 && <EmptyText>No tracker rules yet.</EmptyText>}
          </div>
        </Card>
      </div>
    </section>
  );
}

function SettingsPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title="Settings" subtitle="General, notification, sound, menubar, window, display, account, support and developer controls." />
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <Card title="General" action="Timer">
          <NumberRow label="Daily goal (min)" value={state.settings.dailyGoalMinutes} onChange={(v) => dispatch({ type: "settings", patch: { dailyGoalMinutes: v } })} />
          <NumberRow label="Snap timer interval (min)" value={state.settings.snapIntervalMinutes} onChange={(v) => dispatch({ type: "settings", patch: { snapIntervalMinutes: v } })} />
          <Toggle label="Auto-start Session when suggestion is selected" checked={state.settings.autoStartSuggestion} onChange={(v) => dispatch({ type: "settings", patch: { autoStartSuggestion: v } })} />
          <Toggle label="Ask for reflection when Session has ended" checked={state.settings.askReflection} onChange={(v) => dispatch({ type: "settings", patch: { askReflection: v } })} />
          <Toggle label="Launch at login" checked={state.settings.launchAtLogin} onChange={(v) => dispatch({ type: "settings", patch: { launchAtLogin: v } })} />
        </Card>
        <Card title="Background sound" action={state.settings.backgroundSoundEnabled ? "On" : "Off"}>
          <Toggle label="Play background sound" checked={state.settings.backgroundSoundEnabled} onChange={(v) => dispatch({ type: "settings", patch: { backgroundSoundEnabled: v } })} />
          <SelectRow label="Session sound" value={state.settings.sessionSound} options={SOUND_OPTIONS} onChange={(v) => dispatch({ type: "settings", patch: { sessionSound: v } })} />
          <RangeRow label="Session volume" value={state.settings.sessionVolume} onChange={(v) => dispatch({ type: "settings", patch: { sessionVolume: v } })} />
          <SelectRow label="Session end sound" value={state.settings.sessionEndSound} options={SOUND_OPTIONS} onChange={(v) => dispatch({ type: "settings", patch: { sessionEndSound: v } })} />
          <RangeRow label="Session end volume" value={state.settings.sessionEndVolume} onChange={(v) => dispatch({ type: "settings", patch: { sessionEndVolume: v } })} />
          <SelectRow label="Break sound" value={state.settings.breakSound} options={SOUND_OPTIONS} onChange={(v) => dispatch({ type: "settings", patch: { breakSound: v } })} />
          <RangeRow label="Break volume" value={state.settings.breakVolume} onChange={(v) => dispatch({ type: "settings", patch: { breakVolume: v } })} />
          <SelectRow label="Break end sound" value={state.settings.breakEndSound} options={SOUND_OPTIONS} onChange={(v) => dispatch({ type: "settings", patch: { breakEndSound: v } })} />
          <RangeRow label="Break end volume" value={state.settings.breakEndVolume} onChange={(v) => dispatch({ type: "settings", patch: { breakEndVolume: v } })} />
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton icon={<ZapIcon size={14} />} label="Preview session" onClick={() => dispatch({ type: "sound-test", now: Date.now(), slot: "session" })} />
            <ActionButton icon={<ZapIcon size={14} />} label="Preview session end" onClick={() => dispatch({ type: "sound-test", now: Date.now(), slot: "session-end" })} />
            <ActionButton icon={<ZapIcon size={14} />} label="Preview break" onClick={() => dispatch({ type: "sound-test", now: Date.now(), slot: "break" })} />
            <ActionButton icon={<ZapIcon size={14} />} label="Preview break end" onClick={() => dispatch({ type: "sound-test", now: Date.now(), slot: "break-end" })} />
          </div>
        </Card>
        <Card title="Menubar and Dock" action="Chrome">
          <Toggle label="Show duration on menubar" checked={state.settings.menuShowDuration} onChange={(v) => dispatch({ type: "settings", patch: { menuShowDuration: v } })} />
          <Toggle label="Show category on menubar" checked={state.settings.menuShowCategory} onChange={(v) => dispatch({ type: "settings", patch: { menuShowCategory: v } })} />
          <Toggle label="Show total focus time today" checked={state.settings.menuShowTodayTotal} onChange={(v) => dispatch({ type: "settings", patch: { menuShowTodayTotal: v } })} />
          <Toggle label="Show icon on dock" checked={state.settings.showDockIcon} onChange={(v) => dispatch({ type: "settings", patch: { showDockIcon: v } })} />
        </Card>
        <Card title="Window" action="Mini player">
          <Toggle label="Keep app on top" checked={state.settings.keepWindowOnTop} onChange={(v) => dispatch({ type: "settings", patch: { keepWindowOnTop: v } })} />
          <Toggle label="Keep app on top while on break" checked={state.settings.keepWindowOnTopOnBreak} onChange={(v) => dispatch({ type: "settings", patch: { keepWindowOnTopOnBreak: v } })} />
          <Toggle label="Show on all spaces" checked={state.settings.showOnAllSpaces} onChange={(v) => dispatch({ type: "settings", patch: { showOnAllSpaces: v } })} />
          <Toggle label="Minimize when Session starts" checked={state.settings.minimizeWhenStarted} onChange={(v) => dispatch({ type: "settings", patch: { minimizeWhenStarted: v } })} />
          <PrimaryButton className="mt-3" icon={<Maximize2Icon size={14} />} label="Toggle Mini Player" onClick={() => dispatch({ type: "mini", value: !state.miniPlayerOpen })} />
        </Card>
        <Card title="Display and language" action={state.settings.theme}>
          <SelectRow label="Theme" value={state.settings.theme} options={["system", "dark", "light"]} onChange={(v) => dispatch({ type: "settings", patch: { theme: v as PomodoroSettings["theme"] } })} />
          <SelectRow label="Language" value={state.settings.language} options={["en", "es", "fr", "de", "ja", "ko", "pt-BR"]} onChange={(v) => dispatch({ type: "settings", patch: { language: v } })} />
          <Toggle label="Local keyboard shortcuts" checked={state.settings.localShortcutsEnabled} onChange={(v) => dispatch({ type: "settings", patch: { localShortcutsEnabled: v } })} />
          <Toggle label="Global keyboard shortcuts" checked={state.settings.globalShortcutsEnabled} onChange={(v) => dispatch({ type: "settings", patch: { globalShortcutsEnabled: v } })} />
        </Card>
        <Card title="Account and support" action="Local">
          <ActionButton icon={<RefreshCwIcon size={14} />} label="Rebuild analytics data" onClick={() => dispatch({ type: "notice", now: Date.now(), title: "Analytics rebuilt", detail: "Local logs were recalculated." })} />
          <ActionButton className="mt-2" icon={<DownloadIcon size={14} />} label="Export data" onClick={() => download("session-export.json", JSON.stringify(state, null, 2), "application/json")} />
          <ActionButton className="mt-2" icon={<EllipsisIcon size={14} />} label="Support request" onClick={() => dispatch({ type: "notice", now: Date.now(), title: "Support", detail: "Support action captured locally." })} />
        </Card>
      </div>
    </section>
  );
}

function PanelButton({ panel, current, icon, label, onClick }: { panel: Panel; current: Panel; icon: React.ReactNode; label: string; onClick: (panel: Panel) => void }) {
  return (
    <button onClick={() => onClick(panel)} className={cx("flex h-9 items-center gap-2 rounded-[8px] px-2.5 text-left text-[12.5px]", current === panel ? "bg-[rgba(255,255,255,0.10)] text-[var(--color-fg)]" : "text-[var(--color-menu-row-text)] hover:bg-[rgba(255,255,255,0.04)]")}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

function Header({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div>
      <div className="text-[18px] font-bold">{title}</div>
      <div className="text-[12px] text-[var(--color-fg-secondary)]">{subtitle}</div>
    </div>
  );
}

function Card({ title, action, children }: { title: string; action?: string; children: React.ReactNode }) {
  return (
    <div className="rounded-[10px] border border-[var(--color-border)] bg-[var(--color-card)] p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="text-[13px] font-bold">{title}</div>
        {action && <div className="text-[11px] text-[var(--color-fg-secondary)]">{action}</div>}
      </div>
      {children}
    </div>
  );
}

function DayHeader({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const selected = new Date(`${state.selectedDate}T12:00:00`);
  const shift = (days: number) => {
    const next = new Date(selected);
    next.setDate(selected.getDate() + days);
    dispatch({ type: "selected-date", value: dateKey(next) });
  };
  return (
    <div className="rounded-[10px] border border-[var(--color-border)] bg-[var(--color-card)] p-4">
      <div className="flex items-center justify-between">
        <button className="icon-btn" onClick={() => shift(-1)} aria-label="Previous day"><ArrowLeftIcon size={14} /></button>
        <div className="text-center">
          <div className="text-[13px] font-bold">{state.selectedDate === dateKey(Date.now()) ? "Today" : state.selectedDate}</div>
          <div className="text-[11px] text-[var(--color-fg-secondary)]">{selected.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" })}</div>
        </div>
        <button className="icon-btn" onClick={() => shift(1)} aria-label="Next day"><ArrowRightIcon size={14} /></button>
      </div>
    </div>
  );
}

function StatsGrid({ state }: { state: PomodoroState }) {
  const focus = totalFocusSeconds(state, state.selectedDate);
  const breaks = totalBreakSeconds(state, state.selectedDate);
  const dayLogs = state.logs.filter((log) => sameDay(log.startAt, state.selectedDate) && !log.abandoned);
  const focused = dayLogs.filter((log) => log.mood === "focused").length;
  const neutral = dayLogs.filter((log) => log.mood === "neutral").length;
  const distracted = dayLogs.filter((log) => log.mood === "distracted").length;
  return (
    <div className="grid grid-cols-3 gap-3">
      <Stat label="Total focus" value={formatDuration(focus)} />
      <Stat label="Total break" value={formatDuration(breaks)} />
      <Stat label="Focus/break" value={`${Math.round(focus / 60)}/${Math.max(1, Math.round(breaks / 60))}`} />
      <Stat label="Focused" value={`${focused}`} />
      <Stat label="Neutral" value={`${neutral}`} />
      <Stat label="Distracted" value={`${distracted}`} />
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[10px] border border-[var(--color-border)] bg-[var(--color-card)] p-3">
      <div className="text-[18px] font-bold">{value}</div>
      <div className="text-[11px] uppercase text-[var(--color-fg-secondary)]">{label}</div>
    </div>
  );
}

function Timeline({ state, large }: { state: PomodoroState; large?: boolean }) {
  const logs = state.logs.filter((log) => sameDay(log.startAt, state.selectedDate) && !log.abandoned);
  const projected = state.active && sameDay(state.active.startAt, state.selectedDate) ? state.active : null;
  return (
    <Card title="Timeline" action={large ? "Day view" : "Current day"}>
      <div className={cx("relative overflow-hidden rounded-[8px] border border-[var(--color-border-subtle)] bg-[rgba(0,0,0,0.18)]", large ? "h-[560px]" : "h-[220px]")}>
        {Array.from({ length: 9 }, (_, i) => i + 9).map((hour) => (
          <div key={hour} className="absolute left-0 right-0 border-t border-[rgba(255,255,255,0.06)]" style={{ top: `${((hour - 9) / 9) * 100}%` }}>
            <span className="ml-2 text-[10px] text-[var(--color-fg-tertiary)]">{hour}:00</span>
          </div>
        ))}
        {logs.map((log) => <TimelineBlock key={log.id} log={log} state={state} />)}
        {projected && (
          <div className="absolute left-[58%] w-[32%] rounded-[6px] border border-[rgba(239,91,91,0.55)] bg-[rgba(239,91,91,0.22)]" style={{ top: `${timeTop(projected.startAt)}%`, height: `${Math.max(6, projected.totalSec / 324)}%` }} />
        )}
      </div>
    </Card>
  );
}

function TimelineBlock({ log, state }: { log: PomodoroLog; state: PomodoroState }) {
  const category = state.categories.find((cat) => cat.id === log.categoryId);
  return (
    <div className="absolute left-[14%] w-[38%] rounded-[6px] px-2 py-1 text-[10px] text-white" style={{ top: `${timeTop(log.startAt)}%`, height: `${Math.max(6, log.durationSec / 324)}%`, background: category?.color ?? "#666" }}>
      <div className="truncate">{log.kind === "break" ? "Break" : log.intention || "Focus"}</div>
    </div>
  );
}

function Distribution({ state }: { state: PomodoroState }) {
  const focusLogs = state.logs.filter((log) => log.kind === "focus" && sameDay(log.startAt, state.selectedDate) && !log.abandoned);
  const total = focusLogs.reduce((sum, log) => sum + log.durationSec, 0);
  return (
    <div className="space-y-2">
      {state.categories.map((cat) => {
        const sec = focusLogs.filter((log) => log.categoryId === cat.id).reduce((sum, log) => sum + log.durationSec, 0);
        if (!sec) return null;
        return (
          <div key={cat.id}>
            <div className="flex justify-between text-[12px]"><span>{cat.name}</span><span>{formatDuration(sec)}</span></div>
            <div className="mt-1 h-1.5 rounded-full bg-[rgba(255,255,255,0.08)]"><div className="h-full rounded-full" style={{ width: `${(sec / Math.max(1, total)) * 100}%`, background: cat.color }} /></div>
          </div>
        );
      })}
      {total === 0 && <EmptyText>No focus distribution yet.</EmptyText>}
    </div>
  );
}

function MoodDistribution({ logs }: { logs: PomodoroLog[] }) {
  return (
    <div className="grid grid-cols-3 gap-2">
      {(["focused", "neutral", "distracted"] as Mood[]).map((mood) => <Stat key={mood} label={mood} value={`${logs.filter((log) => log.mood === mood).length}`} />)}
    </div>
  );
}

function LogRow({ log, state }: { log: PomodoroLog; state: PomodoroState }) {
  const category = state.categories.find((cat) => cat.id === log.categoryId);
  return (
    <div className="rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="truncate text-[13px]">{log.kind === "break" ? "Break" : log.intention || "Focus"}</div>
          <div className="text-[11px] text-[var(--color-fg-secondary)]">{category?.name ?? "No category"} / {formatDuration(log.durationSec)} / pauses {formatDuration(log.pausesSec)}</div>
        </div>
        <span className="chip">{log.mood ?? log.kind}</span>
      </div>
      {log.notes && <div className="mt-2 text-[12px] text-[var(--color-fg-secondary)]">{log.notes}</div>}
    </div>
  );
}

function WebsiteBlockerCard({ title, rule, onChange }: { title: string; rule: BlockerRule; onChange: (rule: BlockerRule) => void }) {
  return (
    <Card title={title} action={rule.type === "deny" ? "Deny list" : "Allow list"}>
      <Toggle label="Enable website blocker" checked={rule.enabled} onChange={(v) => onChange({ ...rule, enabled: v })} />
      <SelectRow label="Type" value={rule.type} options={["deny", "allow"]} onChange={(v) => onChange({ ...rule, type: v as BlockerRule["type"] })} />
      <textarea value={rule.entries} onChange={(e) => onChange({ ...rule, entries: e.target.value })} className="field mt-3 min-h-[130px] w-full p-3" placeholder="example.com&#10;social.example" />
      <div className="mt-2 text-[11.5px] text-[var(--color-fg-secondary)]">Entries are enforced as an in-app active blocker list for this example.</div>
    </Card>
  );
}

function AppBlockerCard({ title, enabled, apps, onChange }: { title: string; enabled: boolean; apps: string[]; onChange: (enabled: boolean, apps: string[]) => void }) {
  return (
    <Card title={title} action={`${apps.length} apps`}>
      <Toggle label="Enable app blocker" checked={enabled} onChange={(v) => onChange(v, apps)} />
      <textarea value={apps.join("\n")} onChange={(e) => onChange(enabled, e.target.value.split(/\r?\n/).filter(Boolean))} className="field mt-3 min-h-[130px] w-full p-3" placeholder="App name per line" />
    </Card>
  );
}

function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange: (checked: boolean) => void }) {
  return (
    <label className="flex min-h-9 items-center justify-between gap-4 border-b border-[var(--color-border-subtle)] py-2 text-[12.5px] last:border-b-0">
      <span>{label}</span>
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

function NumberRow({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  return (
    <label className="flex min-h-9 items-center justify-between gap-4 border-b border-[var(--color-border-subtle)] py-2 text-[12.5px] last:border-b-0">
      <span>{label}</span>
      <input type="number" value={value} min={0} onChange={(e) => onChange(Number(e.target.value))} className="field h-8 w-24 text-right" />
    </label>
  );
}

function RangeRow({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  return (
    <label className="block border-b border-[var(--color-border-subtle)] py-2 text-[12.5px] last:border-b-0">
      <div className="flex justify-between"><span>{label}</span><span className="text-[var(--color-fg-secondary)]">{value.toFixed(2)}</span></div>
      <input type="range" min={0} max={1} step={0.01} value={value} onChange={(e) => onChange(Number(e.target.value))} className="mt-2 w-full" />
    </label>
  );
}

function SelectRow({ label, value, options, onChange }: { label: string; value: string; options: string[]; onChange: (value: string) => void }) {
  return (
    <label className="flex min-h-9 items-center justify-between gap-4 border-b border-[var(--color-border-subtle)] py-2 text-[12.5px] last:border-b-0">
      <span>{label}</span>
      <select value={value} onChange={(e) => onChange(e.target.value)} className="h-8 rounded-[8px] border border-[var(--color-border)] bg-[rgba(255,255,255,0.04)] px-2 text-[12px]">
        {options.map((option) => <option key={option} value={option}>{option}</option>)}
      </select>
    </label>
  );
}

function ActionButton({ icon, label, onClick, className }: { icon: React.ReactNode; label: string; onClick: () => void; className?: string }) {
  return (
    <button onClick={onClick} className={cx("inline-flex h-9 items-center gap-1.5 rounded-[8px] bg-[rgba(255,255,255,0.07)] px-3 text-[12px] hover:bg-[rgba(255,255,255,0.10)]", className)}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

function PrimaryButton({ icon, label, onClick, className }: { icon: React.ReactNode; label: string; onClick: () => void; className?: string }) {
  return (
    <button onClick={onClick} className={cx("inline-flex h-9 items-center gap-1.5 rounded-[8px] bg-[var(--color-destructive)] px-3 text-[12px] font-bold text-white hover:brightness-110", className)}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

function DownloadButton({ filename, data, label, mime }: { filename: string; data: string; label: string; mime: string }) {
  return <ActionButton icon={<DownloadIcon size={14} />} label={label} onClick={() => download(filename, data, mime)} />;
}

function CodeLine({ value }: { value: string }) {
  return <div className="mb-2 rounded-[8px] bg-black p-2 font-mono text-[11px] text-[var(--color-fg-secondary)]">{value}</div>;
}

function RuleText({ text }: { text: string }) {
  return <div className="rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">{text}</div>;
}

function EmptyText({ children }: { children: React.ReactNode }) {
  return <div className="text-[12px] text-[var(--color-fg-secondary)]">{children}</div>;
}

function filterLogs(logs: PomodoroLog[], state: PomodoroState): PomodoroLog[] {
  return logs
    .filter((log) => sameDay(log.startAt, state.selectedDate))
    .filter((log) => !state.notesOnly || !!log.notes)
    .filter((log) => {
      if (state.reportFilter === "all") return true;
      if (state.reportFilter === "notes") return !!log.notes;
      return log.kind === state.reportFilter;
    })
    .sort((a, b) => b.startAt - a.startAt);
}

function parseUrlCommand(location: Location): { command: PomodoroUrlCommand; intention?: string; categoryId?: string } | null {
  const params = new URLSearchParams(location.search);
  const hash = new URLSearchParams(location.hash.replace(/^#/, ""));
  const raw = params.get("session") ?? params.get("sessionAction") ?? hash.get("session") ?? hash.get("sessionAction");
  if (!raw || !isUrlCommand(raw)) return null;
  return {
    command: raw,
    intention: params.get("intention") ?? hash.get("intention") ?? undefined,
    categoryId: params.get("category") ?? hash.get("category") ?? undefined,
  };
}

function isUrlCommand(value: string): value is PomodoroUrlCommand {
  return value === "start" || value === "pause" || value === "finish" || value === "break" || value === "abandon" || value === "status";
}

function timeTop(timestamp: number): number {
  const date = new Date(timestamp);
  const minutes = date.getHours() * 60 + date.getMinutes();
  const start = 9 * 60;
  const end = 18 * 60;
  return Math.max(0, Math.min(100, ((minutes - start) / (end - start)) * 100));
}

function download(filename: string, data: string, mime: string) {
  const blob = new Blob([data], { type: mime });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
