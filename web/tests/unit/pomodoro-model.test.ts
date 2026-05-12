import { describe, expect, it } from "vitest";
import {
  abandonTimer,
  addScheduleItem,
  addWindowTrackerRule,
  currentBlockers,
  adjustTimerMinutes,
  defaultPomodoroState,
  finishTimer,
  formatClock,
  logInReportRange,
  parsePlainTasks,
  pauseTimer,
  resumeTimer,
  reportRangeLabel,
  scheduledItemsForDate,
  startBreak,
  startScheduleItem,
  runTimerEndMainAction,
  runPomodoroShortcut,
  runPomodoroUrlCommand,
  startFocus,
  testNotificationProfile,
  testSoundProfile,
  testWindowTracker,
  tickPomodoro,
  totalFocusSeconds,
  undoAbandon,
  updateTaskEstimate,
} from "../../src/screens/pomodoro/pomodoro-model";

describe("pomodoro model", () => {
  it("starts, pauses, resumes and saves focus time", () => {
    const now = Date.UTC(2026, 4, 12, 9, 0, 0);
    let state = defaultPomodoroState(now);
    state = startFocus(state, now, "Write spec", "general", 25);
    state = tickPomodoro(state, now + 5 * 60 * 1000);
    expect(state.active?.remainingSec).toBe(20 * 60);

    state = pauseTimer(state, now + 5 * 60 * 1000);
    state = resumeTimer(state, now + 7 * 60 * 1000);
    expect(state.active?.pausesSec).toBe(120);

    state = finishTimer(state, now + 12 * 60 * 1000, "focused", "Clear progress");
    expect(state.logs).toHaveLength(1);
    expect(state.logs[0]?.durationSec).toBe(10 * 60);
    expect(state.logs[0]?.pausesSec).toBe(120);
    expect(totalFocusSeconds(state, "2026-05-12")).toBe(10 * 60);
  });

  it("supports timer adjustment and end transition", () => {
    const now = Date.UTC(2026, 4, 12, 10, 0, 0);
    let state = startFocus(defaultPomodoroState(now), now, "Review", "general", 10);
    state = adjustTimerMinutes(state, now, 5);
    expect(state.active?.totalSec).toBe(15 * 60);
    state = tickPomodoro(state, now + 15 * 60 * 1000);
    expect(state.active?.mode).toBe("ended");
    expect(state.active?.remainingSec).toBe(0);
  });

  it("auto-starts a break after focus when enabled", () => {
    const now = Date.UTC(2026, 4, 12, 10, 30, 0);
    let state = defaultPomodoroState(now);
    state.settings.autoStartBreak = true;
    state.settings.shortBreakMinutes = 3;

    state = startFocus(state, now, "Auto break", "general", 1);
    state = tickPomodoro(state, now + 60_000);

    expect(state.logs.at(-1)?.kind).toBe("focus");
    expect(state.logs.at(-1)?.durationSec).toBe(60);
    expect(state.active?.mode).toBe("break");
    expect(state.active?.totalSec).toBe(3 * 60);
  });

  it("auto-starts focus after break when enabled", () => {
    const now = Date.UTC(2026, 4, 12, 10, 45, 0);
    let state = defaultPomodoroState(now);
    state.settings.autoStartFocus = true;
    state.settings.sessionMinutes = 4;
    state.intentionDraft = "Next automatic focus";

    state = startBreak(state, now, 1);
    state = tickPomodoro(state, now + 60_000);

    expect(state.logs.at(-1)?.kind).toBe("break");
    expect(state.logs.at(-1)?.durationSec).toBe(60);
    expect(state.active?.mode).toBe("focus");
    expect(state.active?.intention).toBe("Next automatic focus");
    expect(state.active?.totalSec).toBe(4 * 60);
  });

  it("runs the configured focus end main action", () => {
    const now = Date.UTC(2026, 4, 12, 10, 55, 0);
    let state = defaultPomodoroState(now);
    state.settings.sessionMainAction = "break";
    state.settings.shortBreakMinutes = 2;

    state = startFocus(state, now, "Main action", "general", 1);
    state = tickPomodoro(state, now + 60_000);
    expect(state.active?.mode).toBe("ended");

    state = runTimerEndMainAction(state, now + 61_000, "focused", "Done");
    expect(state.logs.at(-1)?.kind).toBe("focus");
    expect(state.logs.at(-1)?.notes).toBe("Done");
    expect(state.active?.mode).toBe("break");
    expect(state.active?.totalSec).toBe(2 * 60);
  });

  it("runs the configured break end main action", () => {
    const now = Date.UTC(2026, 4, 12, 11, 5, 0);
    let state = defaultPomodoroState(now);
    state.settings.breakMainAction = "start-session";
    state.settings.sessionMinutes = 3;
    state.intentionDraft = "After break";

    state = startBreak(state, now, 1);
    state = tickPomodoro(state, now + 60_000);
    expect(state.active?.mode).toBe("ended");

    state = runTimerEndMainAction(state, now + 61_000);
    expect(state.logs.at(-1)?.kind).toBe("break");
    expect(state.active?.mode).toBe("focus");
    expect(state.active?.intention).toBe("After break");
    expect(state.active?.totalSec).toBe(3 * 60);
  });

  it("can undo an abandoned timer", () => {
    const now = Date.UTC(2026, 4, 12, 11, 0, 0);
    let state = startFocus(defaultPomodoroState(now), now, "Draft", "general", 25);
    state = abandonTimer(state, now + 60_000);
    expect(state.lastAbandoned?.abandoned).toBe(true);
    state = undoAbandon(state, now + 61_000);
    expect(state.logs).toHaveLength(1);
    expect(state.logs[0]?.abandoned).toBe(false);
  });

  it("parses plain text tasks and formats clocks", () => {
    const tasks = parsePlainTasks("- One\nTwo\n\n* Three", "general");
    expect(tasks.map((task) => task.title)).toEqual(["One", "Two", "Three"]);
    expect(formatClock(65)).toBe("1:05");
  });

  it("starts tasks with their edited estimate", () => {
    const now = Date.UTC(2026, 4, 12, 11, 30, 0);
    let state = defaultPomodoroState(now);
    state.tasks = parsePlainTasks("Estimate task", "general");
    state = updateTaskEstimate(state, state.tasks[0]!.id, 45);
    expect(state.tasks[0]?.estimateMinutes).toBe(45);

    state = startFocus(state, now, state.tasks[0]!.title, state.tasks[0]!.categoryId, state.tasks[0]!.estimateMinutes);
    expect(state.active?.totalSec).toBe(45 * 60);
  });

  it("only enforces blockers while focus or break is active", () => {
    const now = Date.UTC(2026, 4, 12, 12, 0, 0);
    let state = defaultPomodoroState(now);
    state.settings.sessionWebBlocker = { enabled: true, type: "deny", entries: "news.example" };
    expect(currentBlockers(state)).toEqual([]);

    state = startFocus(state, now, "Block check", "general", 25);
    expect(currentBlockers(state)).toEqual(["Web: news.example"]);

    state = pauseTimer(state, now + 60_000);
    expect(currentBlockers(state)).toEqual([]);
  });

  it("applies local profile rules for reading focus and learn blockers", () => {
    const now = Date.UTC(2026, 4, 12, 12, 30, 0);
    let state = defaultPomodoroState(now);
    state.settings.sessionWebBlocker = { enabled: true, type: "deny", entries: "news.example" };

    state = startFocus(state, now, "Reading design notes", "general", 25);
    expect(state.active?.totalSec).toBe(30 * 60);
    state = finishTimer(state, now + 60_000);

    state = startFocus(state, now + 120_000, "learn shortcuts", "general", 25);
    expect(currentBlockers(state)).toEqual([]);
  });

  it("runs shortcut actions against the timer state", () => {
    const now = Date.UTC(2026, 4, 12, 13, 0, 0);
    let state = defaultPomodoroState(now);

    state = runPomodoroShortcut(state, "Start focus", now, "Shortcut focus");
    expect(state.active?.mode).toBe("focus");
    expect(state.active?.intention).toBe("Shortcut focus");

    state = runPomodoroShortcut(state, "Pause / unpause", now + 60_000);
    expect(state.active?.mode).toBe("paused");

    state = runPomodoroShortcut(state, "Pause / unpause", now + 120_000);
    expect(state.active?.mode).toBe("focus");

    state = runPomodoroShortcut(state, "Update intention", now + 121_000, "Updated shortcut");
    expect(state.active?.intention).toBe("Updated shortcut");

    state = runPomodoroShortcut(state, "Take a break", now + 180_000);
    expect(state.logs.at(-1)?.intention).toBe("Updated shortcut");
    expect(state.active?.mode).toBe("break");
  });

  it("runs local URL scheme commands against the timer state", () => {
    const now = Date.UTC(2026, 4, 12, 14, 0, 0);
    let state = defaultPomodoroState(now);

    state = runPomodoroUrlCommand(state, "start", now, "URL focus", "general");
    expect(state.active?.mode).toBe("focus");
    expect(state.active?.intention).toBe("URL focus");

    state = runPomodoroUrlCommand(state, "pause", now + 30_000);
    expect(state.active?.mode).toBe("paused");

    state = runPomodoroUrlCommand(state, "finish", now + 60_000);
    expect(state.active).toBeNull();
    expect(state.logs.at(-1)?.intention).toBe("URL focus");
  });

  it("adds and tests local window tracker rules", () => {
    const now = Date.UTC(2026, 4, 12, 15, 0, 0);
    let state = defaultPomodoroState(now);

    state = addWindowTrackerRule(state, now, "Safari", "Reading", "general", "Read docs");
    expect(state.settings.windowTrackerEnabled).toBe(true);
    expect(state.settings.windowTrackers).toHaveLength(1);

    state = testWindowTracker(state, now + 1_000, "Safari", "Reading reference");
    expect(state.active?.mode).toBe("focus");
    expect(state.active?.intention).toBe("Read docs");
  });

  it("emits local notification profile notices once per threshold", () => {
    const now = Date.UTC(2026, 4, 12, 16, 0, 0);
    let state = defaultPomodoroState(now);
    state.settings.endingSoonMinutes = 2;
    state.settings.presenceEnabled = true;
    state.settings.pauseOverflowEnabled = true;
    state.settings.overflowMinutes = 1;

    state = startFocus(state, now, "Notification check", "general", 4);
    state = tickPomodoro(state, now + 2 * 60 * 1000);
    expect(state.notices[0]?.title).toBe("Ending soon");
    state = tickPomodoro(state, now + 2 * 60 * 1000 + 1_000);
    expect(state.notices[0]?.title).toBe("Presence reminder");
    state = tickPomodoro(state, now + 2 * 60 * 1000 + 2_000);
    expect(state.notices.filter((notice) => notice.title === "Ending soon")).toHaveLength(1);

    state = pauseTimer(state, now + 2 * 60 * 1000 + 3_000);
    state = tickPomodoro(state, now + 3 * 60 * 1000 + 4_000);
    expect(state.notices[0]?.title).toBe("Pause overflow");
  });

  it("can test notification profile actions locally", () => {
    const now = Date.UTC(2026, 4, 12, 17, 0, 0);
    let state = defaultPomodoroState(now);
    state = testNotificationProfile(state, now, "ending-soon");
    state = testNotificationProfile(state, now + 1_000, "presence");
    state = testNotificationProfile(state, now + 2_000, "overflow");
    expect(state.notices.map((notice) => notice.title).slice(0, 3)).toEqual([
      "Overflow reminder",
      "Presence reminder",
      "Ending soon",
    ]);
  });

  it("describes sound profile previews and timer end sounds", () => {
    const now = Date.UTC(2026, 4, 12, 18, 0, 0);
    let state = defaultPomodoroState(now);
    state.settings.sessionEndSound = "Gong";
    state.settings.sessionEndVolume = 0.25;

    state = testSoundProfile(state, now, "session-end");
    expect(state.notices[0]?.detail).toBe("Session end sound: Gong at 25%.");

    state = startFocus(state, now, "Sound check", "general", 1);
    state = tickPomodoro(state, now + 60_000);
    expect(state.active?.mode).toBe("ended");
    expect(state.notices[0]?.detail).toContain("End sound: Gong at 25%.");
  });

  it("plans and starts scheduled calendar sessions locally", () => {
    const now = Date.UTC(2026, 4, 12, 19, 0, 0);
    let state = defaultPomodoroState(now);

    state = addScheduleItem(state, now, "Calendar focus", "deep-work", "09:30", 45);
    const planned = scheduledItemsForDate(state, "2026-05-12");
    expect(planned).toHaveLength(1);
    expect(planned[0]?.startMinutes).toBe(9 * 60 + 30);
    expect(state.notices[0]?.detail).toBe("Calendar focus scheduled at 09:30.");

    state = startScheduleItem(state, now + 1_000, planned[0]!.id);
    expect(state.active?.mode).toBe("focus");
    expect(state.active?.intention).toBe("Calendar focus");
    expect(state.active?.totalSec).toBe(45 * 60);
    expect(state.schedules[0]?.started).toBe(true);
  });

  it("filters analytics by day week and month ranges", () => {
    const now = Date.UTC(2026, 4, 12, 9, 0, 0);
    let state = defaultPomodoroState(now);
    state.logs = [
      {
        id: "monday",
        kind: "focus",
        intention: "Monday",
        categoryId: "general",
        startAt: new Date("2026-05-11T09:00:00").getTime(),
        endAt: new Date("2026-05-11T09:25:00").getTime(),
        durationSec: 25 * 60,
        pausesSec: 0,
      },
      {
        id: "today",
        kind: "focus",
        intention: "Today",
        categoryId: "general",
        startAt: new Date("2026-05-12T09:00:00").getTime(),
        endAt: new Date("2026-05-12T09:25:00").getTime(),
        durationSec: 25 * 60,
        pausesSec: 0,
      },
      {
        id: "previous-month",
        kind: "focus",
        intention: "April",
        categoryId: "general",
        startAt: new Date("2026-04-30T09:00:00").getTime(),
        endAt: new Date("2026-04-30T09:25:00").getTime(),
        durationSec: 25 * 60,
        pausesSec: 0,
      },
    ];

    state.reportRange = "day";
    expect(state.logs.filter((log) => logInReportRange(log, state)).map((log) => log.id)).toEqual(["today"]);

    state.reportRange = "week";
    expect(state.logs.filter((log) => logInReportRange(log, state)).map((log) => log.id)).toEqual(["monday", "today"]);

    state.reportRange = "month";
    expect(state.logs.filter((log) => logInReportRange(log, state)).map((log) => log.id)).toEqual(["monday", "today"]);
    expect(reportRangeLabel(state)).toContain("2026");
  });
});
