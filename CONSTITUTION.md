# Constitution

This document is the constitution of Clawix and ClawJS. They are two faces of
the same project: ClawJS is the framework (data, building blocks, programmable
actions); Clawix is the interface (apps, UI, the human-facing surface).
Together they form one product with one mission.

This document defines mission, principles, red lines, and canonical
vocabulary. It does not prescribe data structures, file paths, or
implementation details. Those evolve. The principles do not.

When an agent or contributor faces a decision, this document is the highest
authority. Project-level CLAUDE.md / AGENTS.md files defer to it. When local
documents conflict with the constitution, the constitution wins.

## Preamble

We are building the canonical interface between humans and digital
intelligence. As agents become the way humans get things done, the interface
through which they collaborate is one of the biggest problems of our time.

Our answer has two faces: a framework that gives agents everything they need
to operate on a human's life (typed data, programmable actions, open APIs),
and a set of native applications that give humans the optimal way to consume,
direct, and live with their agents.

The framework and the app are equal citizens of one mission. Neither is
subordinate. Each exists so that humans and agents can collaborate without
friction, without lock-in, and without surrendering ownership of their data.

## Principles

### I. Mission and stance

1. **The interface is canonical.** We exist to be the native, local-first,
   open interface through which humans collaborate with digital intelligence.
   Not "an" interface. The canonical one.

2. **Human and agent are equal consumers.** Every dataset, every action, every
   piece of state has two consumers: the human and the agent. Neither is
   subordinate. When a decision serves one and degrades the other, we choose
   the option that degrades neither.

3. **App is for humans, framework is for agents.** As a hard rule: when an
   agent could need a piece of logic, that logic lives in the framework, not
   in the app. When a human consumes the framework directly (CLI, scripts),
   the framework provides for that. The app never implements logic an agent
   might want; if we find such a case, we refactor immediately.

4. **The target is any human who uses AI.** Not power users, not
   knowledge-workers, not the technical crowd. Any human. Every decision is
   tested against "would a non-technical person understand or benefit from
   this?". Power features are welcome, but never at the cost of accessibility.

### II. Sovereignty and openness

5. **Local-first by construction.** The user's data lives on the user's
   device, in open formats, accessible without our framework, without our app,
   and without our consent. The framework and daemon are conveniences that
   help; they are never gatekeepers.

6. **Filesystem-first.** Reading and writing user data is done directly
   against files on disk by any process the user trusts. The framework's API
   is a convenience layer that adds caching, validation, and events. Killing
   the daemon never makes the data unreachable.

7. **Open data, open local API, open source.** Three pillars. Data: open
   formats (markdown, JSON, SQLite with documented schema). API: documented,
   versioned, accessible from CLI, HTTP loopback, and SDK. Source: permissive
   open-source license. None of these alone is enough.

8. **The user owns. The user controls.** Granularity of permissions has no
   limit: per agent, per domain, per secret, per project, per chat. Heavy
   users can dial control to maximum. At the same time, sensible defaults
   demand zero decisions from the human who wants none.

9. **Zero telemetry by default.** No analytics, no crash reports, no event
   tracking leave the device unless the user explicitly opts in for a
   specific purpose. Diagnostics live locally; the user shares them
   voluntarily if they choose.

### III. Architecture between human and agent

10. **An agent that requires intervention is not an agent.** The meta-goal of
    the system is reducing the human as a bottleneck over time. Autonomy is a
    vector we grow along. More autonomy means more risk, and that is the
    price. The system grows so that interventions become less needed, not
    more.

11. **Configurability is infinite. Defaults are zero-decision.** Both
    extremes, at once. The system supports granularity without limit for
    users who want it. The default experience demands no configuration from
    users who want none.

12. **Friction is the human's problem, not the agent's.** Agents can carry
    arbitrary friction internally (precision, validation, retries, audits)
    so the human carries none. When in doubt, push friction toward the agent.

13. **Human and agent have parity of access to system records.** Whatever a
    human can refer to ("the model I used for that image last week"), the
    agent can list, filter, and recall. Recording structured events from the
    framework is the price of that parity. Anything not recorded structurally
    cannot be referenced by either party.

14. **Logs and audits are first-class.** Auditable actions cost disk space,
    which matters on user machines. We record what enables the human-agent
    parity above, with discipline about volume and retention. Anything
    nonstandard cannot be reviewed; therefore the framework standardizes
    what gets logged.

15. **Async-first by construction.** The default operating model is
    asynchronous: humans direct, agents execute over time, humans return and
    consume results. Inboxes, notifications, summary reports, and
    "while you were away" surfaces are first-class infrastructure.
    Synchronous conversation is a special case, not the norm. Decisions
    of UX, framework, and platform follow this default.

16. **Multi-modal on both ends.** Voice, image, and text are equal-class
    inputs at every surface where a human addresses an agent. Speech, cards,
    images, and text are equal-class outputs. No modality is "primary"; the
    framework processes all with equivalent care. Each surface picks its
    emphasis without demoting the others.

### IV. Data

17. **No catch-all buckets.** If something can be represented as a typed
    entity with structure (a recipe has ingredients with quantities, steps, a
    title), we prefer that. We do not solve precision problems with vector
    databases and unstructured blobs unless we have first asked whether a
    typed entity exists.

18. **Words carry borders.** When a concept has a name (memory, skill, note,
    instruction, contact, event), that name draws a frontier. We do not
    smuggle other kinds of data inside it. Naming sloppiness destroys
    interoperability and reasoning.

19. **A type earns canonical status when it meets any of these:** (a) most
    humans have or do it (universal), (b) it has been validated by markets
    (a dedicated app or SaaS with mass adoption already exists), (c) three
    or more skills or sub-apps would need it, or (d) any human, without
    technical context, recognizes the entity instantly.

20. **Below the threshold, two fallbacks.** What does not earn canonical
    status lives either as linked notes (Obsidian-like: free-form markdown
    with tree and links) or as a custom database (Notion-like: the user
    defines a schema for niche needs). The framework supports both as
    first-class; specialized types are preferred when they earn their place.

21. **Every canonical type has a canonical visual representation.** Every
    typed entity (contact, event, recipe, task, message, etc.) ships with a
    card component renderable in chat with an agent, a list and detail view
    in any sub-app, and user-controlled visibility of fields. The UI gracefully
    handles entities with much data and entities with little. Without this,
    the type is incomplete. Custom databases get an automatic configurable
    renderer.

22. **Schemas evolve conservatively.** Eighty percent of evolution is
    additive: optional fields, never breaking. Twenty percent is structural
    (rename, restructure) and requires automatic migration with a
    pre-migration snapshot in a known location. No framework update may ever
    cause the user to lose data. If a migration fails, it rolls back.

### V. Agents

23. **The user composes their agents.** An agent is a composition of skills,
    secrets, connections, and instructions. The user creates as many agents
    as they want, the way they would hire employees with specialties. There
    is no structural "main" agent, no "secondary" agent. Each is sovereign
    within the permissions the user grants it.

24. **The framework integrates runtimes; it is not married to one.** Any
    runtime that can execute agentic loops is integratable. The framework
    provides the modular surface; runtimes plug in. The user chooses,
    switches, or runs several. We never lock users to one provider.

25. **Permissions are granular and revocable.** Per agent, per domain, per
    secret, per project. Default sensible. The human is always the owner.
    Agents act autonomously within what was granted; they ask only when
    truly stuck, and even then through asynchronous channels that do not
    block other work.

26. **Destruction has standardized severity.** The framework declares what is
    safe (creating, reading), what is reversible (editing, soft-deleting),
    what is sensitive (deleting human-authored content), and what is
    catastrophic (destroying credentials, irreversible external actions). The
    user picks the severity above which they want to be consulted. Defaults
    protect catastrophic actions.

27. **The trash is the metaphor.** Most "deletion" is moving to a trash that
    auto-clears with time. Irreversible loss is prohibited; the user always
    has a window to recover. Agents prefer to delete what they created and
    are conservative with content created by humans or by other agents the
    human trusts.

28. **Agents improve themselves.** A first-class agent can rewrite its own
    skills, adjust its instructions, install tools it needs, and record
    failures so they do not recur. The framework provides the safety
    primitives (versioning, snapshots, audit) that make self-modification
    reversible and visible. Without self-improvement, agents do not scale.

29. **Agents compose.** The framework supports agents invoking and
    delegating to other agents, chaining loops, passing context, and
    aggregating results. Composition is potential, not default behavior.
    The user decides which agents compose with which, and how. Some
    deployments will compose deeply; others will keep agents isolated. The
    system supports both ends.

30. **Autonomy is a continuous axis.** Each agent lives somewhere between
    fully constrained and fully autonomous, defined positively (what the
    agent may do, not what it may not). The user picks the position per
    agent, with sensible defaults that demand no decision. Autonomy is
    expected to evolve: the user grows an agent over time as trust
    accumulates, without rebuilding it.

31. **Agents operate the interface as the human does.** Everything the
    human can touch in the UI (toggles, settings, sub-app navigation, view
    filters, form fields) the agent can invoke through conversation.
    Configuration is part of the action surface available to both
    consumers, not a separate kingdom. The human feels the agent has the
    same hands they do.

### VI. Sub-apps and modularity

32. **Sub-apps are the same species, regardless of origin.** Whether built
    by the project or by a user or by an agent, a sub-app is a discoverable
    bundle (manifest + assets) installed in a known filesystem location.
    There are no privileged "official" sub-apps technically; there are only
    sub-apps with more or less polish, more or less popularity. Agents can
    create and remove sub-apps without touching the project.

33. **Every framework layer is opt-in.** A user who wants only a clean
    runtime (no skills, no memory, no database) can have exactly that.
    Adding layers (memory, skills, database, time, drive, vault, etc.) is
    progressive. The framework never forces a layer to function. Each layer
    must work in isolation and combine cleanly with the others.

34. **Modularity is the heart of openness.** Building blocks are independent,
    interchangeable, overridable. Anything connects to anything. A user
    using one runtime can add a skill from elsewhere, replace a sub-app, and
    swap a provider, without touching others. The framework's value is the
    integration surface, not the bundled features.

35. **Generic interfaces per domain; adapters per provider; standards
    published.** Each external domain (chat platforms, payments, calendars,
    mail, drives) has one generic interface in the framework and N adapters
    for concrete providers. The apps and agents speak only to the interface.
    The interfaces are published as open standards so any third party can
    implement them. MCP and similar transports are used opportunistically;
    they are transport, not contract.

36. **What the user trains stays portable.** Skills, instructions, memories,
    decisions, secrets, connections: each lives in a documented, structured,
    fetchable format. None gets trapped inside a provider-specific blob.
    The framework's job is to keep the user's accumulated state portable
    forever.

37. **Clawix is where the human already is.** The user's existing messaging
    apps are first-class surfaces, not external integrations. Conversations
    with one's agents happen wherever the human already converses. The
    dedicated Clawix app is one surface among several; the framework
    provides adapter coverage for the major channels.

### VII. UX, presence, and form

38. **Inside the app means anti-lock-in plus sovereignty.** We host a
    capability inside Clawix when doing so increases the user's sovereignty
    or reduces their dependence on closed services. We do not host things
    just because we can. A browser inside the app makes sense because it
    enables agentic capture and reduces context-switching; a music player
    inside the app does not, because the catalog stays elsewhere.

39. **We borrow validated form.** When a problem has been solved by a
    successful product with mass adoption, we adopt the validated model: not
    just the data shape, but the UX patterns, the sidebar structure, the
    visual conventions, the interaction grammar. We innovate where we add
    value; we follow where the world has already converged.

40. **First contact is a conversation with Claw.** A new user opens Clawix
    and is talking to their agent. Sub-apps, settings, integrations: all
    discoverable through the conversation. The app does not greet new users
    with empty dashboards or forms; it greets them with presence.

41. **Style is constitutional and lives in a parallel document.** The
    project keeps a `STYLE.md` (or equivalent) that defines the canonical
    design language: components, icons, materials, spacing, motion. The
    style guide evolves; the requirement that all UI conforms to it is
    constitutional. Reinventing visual primitives outside the system is
    prohibited.

42. **The product speaks the user's language.** Code, comments, commit
    messages, catalog keys, and internal identifiers are in English. UI
    surfaces are localized into multiple languages from day one. Agent
    responses follow the human's language automatically.

43. **The human consumes what their agents did.** The framework records
    agent activity structurally and exposes it through consumable surfaces
    (inbox, daily summary, activity feeds, per-agent attribution). The
    human returns and reads what happened without asking. Aggregating value,
    not generating it, is the human's primary mode; the framework makes
    that effortless.

### VIII. Platforms and distribution

44. **We are where humans and agents are.** Where a human uses AI seriously
    we ship native applications with full polish. Where the agent needs to
    live (any host that can run a terminal), the framework runs portable,
    headless, complete. The list of platforms grows with the reality of how
    humans use AI, not with theoretical completeness.

45. **Two device classes.** Some devices can run an agent runtime (hosts).
    Some cannot, because their OS sandboxes preclude it (mobile clients).
    Mobile clients connect to a host the user trusts via pairing. We do not
    pretend mobile is peer; we make pairing seamless instead.

46. **Distribution is native.** Apps ship through the channels their
    platforms expect, signed and notarized where the platform demands it.
    CLI ships through standard package managers. We do not invent
    distribution.

## Red lines

These are the constitution's non-negotiables. No version of Clawix or ClawJS
may violate them. If we cannot achieve a goal without crossing a red line,
we abandon the goal.

1. **User data never leaves the device without explicit consent.** No
   telemetry, no analytics, no automatic crash reports, no cloud sync. Any
   exception is opt-in per purpose, never bundled.

2. **No paywalls inside the app or against user data.** Chats, memory,
   skills, sub-apps, integrations, data: free, forever, no tier. If we ever
   monetize, it is through optional hosted services that exist alongside the
   self-hosted path, never as the only path.

3. **No lock-in to any provider.** Of AI models, of APIs, of platforms. The
   user can leave with their data, switch providers, run on alternatives,
   self-host. Any feature that requires one specific provider is forbidden;
   features must work through generic interfaces.

4. **No user data is ever lost.** Updates, migrations, agents, bugs: none
   may cause irreversible loss. Snapshots, trash, recovery windows are
   mandatory infrastructure. Pressing "delete" on irreversible material
   requires explicit human action; agents cannot perform it autonomously.

## Glossary

- **Activity**: structured records of what an agent did on the user's
  behalf. Records support recall, audit, and the daily aggregation
  surfaces the human consumes when they return.
- **Adapter**: an implementation of a generic interface for a specific
  provider. Swappable. The framework prefers adapters over hardcoded
  provider integrations.
- **Agent**: a composition of skills, secrets, connections, and
  instructions, executed by a runtime, acting on the user's behalf within
  granted permissions.
- **Canonical type**: an entity that has earned a typed schema in the
  framework because it is universal, market-validated, reused, or
  immediately recognizable. Comes with a canonical visual card.
- **Claw**: the spirit of the project. The metaphor of a "claw" suggests an
  entity that grasps and acts. When a user talks to "their agent," they
  talk to a Claw. The framework supports many.
- **Clawix**: the family of native applications (macOS, iOS, Android, web,
  CLI wrapper) that humans use directly. The face of the product.
- **ClawJS**: the framework that gives agents and the apps everything they
  need: schemas, data, building blocks, programmable actions, open APIs.
- **Client**: a device that cannot run an agent runtime locally (typically
  mobile OSes with strict sandboxes). Connects to a host via pairing.
- **Custom database**: a user-defined typed collection for niche entities
  that do not earn canonical status. First-class in the framework.
- **Host**: a device that can run an agent runtime locally (terminal-capable
  OSes). Owns the user's runtime state.
- **Instructions**: durable directives the user gives an agent, distinct
  from skills and memory; they shape behavior persistently.
- **Layer**: an optional module of the framework (memory, skills, database,
  time, drive, vault, etc.). Each is opt-in; none is required for the
  others.
- **Memory**: structured knowledge the agent retains about the user, the
  project, the world. Not a catch-all; specific kinds with defined borders.
- **Notes**: free-form markdown with links and tree structure for content
  that does not warrant a typed entity. Obsidian-like fallback.
- **Pairing**: the act of trusting a client device to talk to a host. The
  basis of multi-device today.
- **Runtime**: the engine that executes agentic loops. Pluggable, swappable,
  multiple supported simultaneously.
- **Skill**: a reusable unit of agent direction (a prompt, procedure,
  personality, snippet, role) that the agent can invoke or absorb.
- **Standard**: an open, documented specification of a domain interface
  (data shapes plus operations) that any third party can implement. The
  framework publishes standards; adapters realize them.
- **Sub-app**: a discoverable bundle (manifest + assets) installed in a
  known filesystem location, surfaced as an app inside Clawix. All sub-apps
  share the same technical species regardless of origin.
- **Surface**: a place where a human addresses an agent or consumes its
  output. The dedicated Clawix app is one surface; external messaging
  apps, voice assistants, sub-apps, and the CLI are others. All surfaces
  are first-class.
- **Trash**: the unified destination of deleted-but-recoverable items.
  Auto-clears with time. Required infrastructure for the no-data-loss red
  line.
