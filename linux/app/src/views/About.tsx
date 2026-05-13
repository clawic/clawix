export default function About() {
  return (
    <section class="h-full overflow-auto px-8 py-10">
      <div class="max-w-md mx-auto space-y-3">
        <h1 class="text-xl font-semibold tracking-tightish">About Clawix</h1>
        <p class="text-sm text-zinc-500">
          Clawix is the Linux desktop companion for the Clawix family of apps. It pairs with
          your iPhone, drives dictation locally with whisper.cpp, and orchestrates AI workflows
          through the same bridge protocol the macOS app uses.
        </p>
        <ul class="text-xs text-zinc-500 list-disc pl-5 space-y-1">
          <li>Bridge daemon: clawix-bridge (Swift + SwiftNIO)</li>
          <li>Shell: Tauri 2.x + SolidJS</li>
          <li>Updater: AppImageUpdate / apt</li>
        </ul>
      </div>
    </section>
  );
}
