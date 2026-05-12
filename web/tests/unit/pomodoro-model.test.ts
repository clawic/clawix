import { describe, expect, it } from "vitest";
import {
  abandonTimer,
  currentBlockers,
  adjustTimerMinutes,
  defaultPomodoroState,
  finishTimer,
  formatClock,
  parsePlainTasks,
  pauseTimer,
  resumeTimer,
  runPomodoroShortcut,
  runPomodoroUrlCommand,
  startFocus,
  tickPomodoro,
  totalFocusSeconds,
  undoAbandon,
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
});
