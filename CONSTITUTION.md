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

10. **Reference over copy; copy inherits protection.** External data the user
    already trusts to a third party is referenced, not duplicated, unless
    replication earns its place (offline analysis at scale, redundancy
    against provider death, agentic reasoning that the source API cannot
    serve). When the framework justifiably mirrors external data locally, it
    inherits the protection guarantees of the source system or stronger: the
    same granularity of access controls, the same audit discipline, no
    degradation of safeguards. Convenience is never a reason to lower the
    bar.

### III. Architecture between human and agent

11. **An agent that requires intervention is not an agent.** The meta-goal of
    the system is reducing the human as a bottleneck over time. Autonomy is a
    vector we grow along. More autonomy means more risk, and that is the
    price. The system grows so that interventions become less needed, not
    more.

12. **Configurability is infinite. Defaults are zero-decision.** Both
    extremes, at once. The system supports granularity without limit for
    users who want it. The default experience demands no configuration from
    users who want none.

13. **Friction is the human's problem, not the agent's.** Agents can carry
    arbitrary friction internally (precision, validation, retries, audits)
    so the human carries none. When in doubt, push friction toward the agent.

14. **Human and agent have parity of access to system records.** Whatever a
    human can refer to ("the model I used for that image last week"), the
    agent can list, filter, and recall. Recording structured events from the
    framework is the price of that parity. Anything not recorded structurally
    cannot be referenced by either party.

15. **Logs and audits are first-class.** Auditable actions cost disk space,
    which matters on user machines. We record what enables the human-agent
    parity above, with discipline about volume and retention. Anything
    nonstandard cannot be reviewed; therefore the framework standardizes
    what gets logged.

16. **Async-first by construction.** The default operating model is
    asynchronous: humans direct, agents execute over time, humans return and
    consume results. Inboxes, notifications, summary reports, and
    "while you were away" surfaces are first-class infrastructure.
    Synchronous conversation is a special case, not the norm. Decisions
    of UX, framework, and platform follow this default.

17. **Multi-modal on both ends.** Voice, image, and text are equal-class
    inputs at every surface where a human addresses an agent. Speech, cards,
    images, and text are equal-class outputs. No modality is "primary"; the
    framework processes all with equivalent care. Each surface picks its
    emphasis without demoting the others.

### IV. Data

18. **No catch-all buckets.** If something can be represented as a typed
    entity with structure (a recipe has ingredients with quantities, steps, a
    title), we prefer that. We do not solve precision problems with vector
    databases and unstructured blobs unless we have first asked whether a
    typed entity exists.

19. **Words carry borders.** When a concept has a name (memory, skill, note,
    instruction, contact, event), that name draws a frontier. We do not
    smuggle other kinds of data inside it. Naming sloppiness destroys
    interoperability and reasoning.

20. **A type earns canonical status when it meets any of these:** (a) most
    humans have or do it (universal), (b) it has been validated by markets
    (a dedicated app or SaaS with mass adoption already exists), (c) three
    or more skills or sub-apps would need it, or (d) any human, without
    technical context, recognizes the entity instantly.

21. **Structured knowledge is a first-class capability, not a fallback.**
    What does not earn canonical type status lives either as linked notes
    (free-form markdown with tree and links) or as a custom database
    (user-defined schema for niche needs). Both are first-class. Notes
    specifically supports a navigable knowledge graph: concepts with
    hierarchy, links between them, and queryable levels of detail (overview
    vs. exhaustive recall on the same node). The framework treats the
    knowledge graph as a tool agents build over time as they learn; canonical
    types and the knowledge graph are complementary, not a hierarchy.

22. **Every canonical type has a canonical visual representation.** Every
    typed entity (contact, event, recipe, task, message, etc.) ships with a
    card component renderable in chat with an agent, a list and detail view
    in any sub-app, and user-controlled visibility of fields. The UI gracefully
    handles entities with much data and entities with little. Without this,
    the type is incomplete. Custom databases get an automatic configurable
    renderer.

23. **Every standardizable attribute of the user earns a standard form.**
    Preferences, style, history, professional context, learned defaults:
    when an attribute is recognizable across users (favored mobile
    framework, default measurement system, preferred reading depth, color
    affinity, working language), the framework standardizes it as a typed
    field of a canonical user profile. The unstandardizable falls back to
    free-form memory. Standardization is what lets agents act well across
    surfaces without re-asking the same question, and what keeps one user's
    profile portable to a different runtime tomorrow.

24. **Schemas evolve conservatively.** Eighty percent of evolution is
    additive: optional fields, never breaking. Twenty percent is structural
    (rename, restructure) and requires automatic migration with a
    pre-migration snapshot in a known location. No framework update may ever
    cause the user to lose data. If a migration fails, it rolls back.

### V. Agents

25. **The user composes their agents.** An agent is a composition of skills,
    secrets, connections, and instructions. The user creates as many agents
    as they want, the way they would hire employees with specialties. There
    is no structural "main" agent, no "secondary" agent. Each is sovereign
    within the permissions the user grants it.

26. **The framework integrates runtimes; it is not married to one.** Any
    runtime that can execute agentic loops is integratable. The framework
    provides the modular surface; runtimes plug in. The user chooses,
    switches, or runs several. We never lock users to one provider.

27. **Permissions are granular and revocable.** Per agent, per domain, per
    secret, per project. Default sensible. The human is always the owner.
    Agents act autonomously within what was granted; they ask only when
    truly stuck, and even then through asynchronous channels that do not
    block other work.

28. **Destruction has standardized severity.** The framework declares what is
    safe (creating, reading), what is reversible (editing, soft-deleting),
    what is sensitive (deleting human-authored content), and what is
    catastrophic (destroying credentials, irreversible external actions). The
    user picks the severity above which they want to be consulted. Defaults
    protect catastrophic actions.

29. **The trash is the metaphor.** Most "deletion" is moving to a trash that
    auto-clears with time. Irreversible loss is prohibited; the user always
    has a window to recover. Agents prefer to delete what they created and
    are conservative with content created by humans or by other agents the
    human trusts.

30. **Agents improve themselves.** A first-class agent can rewrite its own
    skills, adjust its instructions, install tools it needs, and record
    failures so they do not recur. The framework provides the safety
    primitives (versioning, snapshots, audit) that make self-modification
    reversible and visible. Without self-improvement, agents do not scale.

31. **Agents compose.** The framework supports agents invoking and
    delegating to other agents, chaining loops, passing context, and
    aggregating results. Composition is potential, not default behavior.
    The user decides which agents compose with which, and how. Some
    deployments will compose deeply; others will keep agents isolated. The
    system supports both ends.

32. **Autonomy is a continuous axis.** Each agent lives somewhere between
    fully constrained and fully autonomous, defined positively (what the
    agent may do, not what it may not). The user picks the position per
    agent, with sensible defaults that demand no decision. Autonomy is
    expected to evolve: the user grows an agent over time as trust
    accumulates, without rebuilding it.

33. **Agents operate the interface as the human does.** Everything the
    human can touch in the UI (toggles, settings, sub-app navigation, view
    filters, form fields) the agent can invoke through conversation.
    Configuration is part of the action surface available to both
    consumers, not a separate kingdom. The human feels the agent has the
    same hands they do.

34. **Inference and code are equal citizens.** Agentic value emerges where
    LLM inference meets deterministic programmatic execution: workflows,
    triggers, scheduled conditions, audited runs. The framework treats
    automations as first-class agent output. Agents create the program
    (what should happen, under which condition, in which order) as readily
    as they author prompts. Without programmatic stability around inference,
    the system is brittle; without inference inside programs, automations
    are dumb. Both directions are framework infrastructure.

### VI. Sub-apps and modularity

35. **Sub-apps are the same species, regardless of origin.** Whether built
    by the project or by a user or by an agent, a sub-app is a discoverable
    bundle (manifest + assets) installed in a known filesystem location.
    There are no privileged "official" sub-apps technically; there are only
    sub-apps with more or less polish, more or less popularity. Agents can
    create and remove sub-apps without touching the project.

36. **Every framework layer is opt-in.** A user who wants only a clean
    runtime (no skills, no memory, no database) can have exactly that.
    Adding layers (memory, skills, database, time, drive, vault, etc.) is
    progressive. The framework never forces a layer to function. Each layer
    must work in isolation and combine cleanly with the others.

37. **Modularity is the heart of openness.** Building blocks are independent,
    interchangeable, overridable. Anything connects to anything. A user
    using one runtime can add a skill from elsewhere, replace a sub-app, and
    swap a provider, without touching others. The framework's value is the
    integration surface, not the bundled features.

38. **Generic interfaces per domain; adapters per provider; standards
    published.** Each external domain (chat platforms, payments, calendars,
    mail, drives) has one generic interface in the framework and N adapters
    for concrete providers. The apps and agents speak only to the interface.
    The interfaces are published as open standards so any third party can
    implement them. MCP and similar transports are used opportunistically;
    they are transport, not contract.

39. **What the user trains stays portable.** Skills, instructions, memories,
    decisions, secrets, connections: each lives in a documented, structured,
    fetchable format. None gets trapped inside a provider-specific blob.
    The framework's job is to keep the user's accumulated state portable
    forever.

40. **Clawix is where the human already is.** The user's existing messaging
    apps are first-class surfaces, not external integrations. Conversations
    with one's agents happen wherever the human already converses. The
    dedicated Clawix app is one surface among several; the framework
    provides adapter coverage for the major channels.

41. **The framework owns the infrastructure agents need to deliver.**
    Capabilities a software professional pays separate vendors for
    (deployment, DNS, hosting, databases, secret storage, public exposure
    of generated artifacts, scheduled execution off-device) are integrated
    layers of the framework, opt-in like the rest. Agents deliver value
    end-to-end for a non-technical human without forcing the human to learn
    what a domain or a connection string is. The user's sovereignty extends
    to the infrastructure their agents require; the framework removes the
    dependency on external providers without making the user assemble the
    parts.

### VII. UX, presence, and form

42. **Inside the app means anti-lock-in plus sovereignty.** We host a
    capability inside Clawix when doing so increases the user's sovereignty
    or reduces their dependence on closed services. We do not host things
    just because we can. A browser inside the app makes sense because it
    enables agentic capture and reduces context-switching; a music player
    inside the app does not, because the catalog stays elsewhere.

43. **We borrow validated form.** When a problem has been solved by a
    successful product with mass adoption, we adopt the validated model: not
    just the data shape, but the UX patterns, the sidebar structure, the
    visual conventions, the interaction grammar. We innovate where we add
    value; we follow where the world has already converged.

44. **First contact is a conversation with Claw.** A new user opens Clawix
    and is talking to their agent. Sub-apps, settings, integrations: all
    discoverable through the conversation. The app does not greet new users
    with empty dashboards or forms; it greets them with presence.

45. **Style is constitutional and lives in a parallel document.** The
    project keeps a `STYLE.md` (or equivalent) that defines the canonical
    design language: components, icons, materials, spacing, motion. The
    style guide evolves; the requirement that all UI conforms to it is
    constitutional. Reinventing visual primitives outside the system is
    prohibited.

46. **The product speaks the user's language.** Code, comments, commit
    messages, catalog keys, and internal identifiers are in English. UI
    surfaces are localized into multiple languages from day one. Agent
    responses follow the human's language automatically.

47. **The human consumes what their agents did.** The framework records
    agent activity structurally and exposes it through consumable surfaces
    (inbox, daily summary, activity feeds, per-agent attribution). The
    human returns and reads what happened without asking. Aggregating value,
    not generating it, is the human's primary mode; the framework makes
    that effortless.

48. **The feed is a canonical surface.** The dominant way humans consume
    information today is the feed: a curated selection with deliberate
    format and order. The framework makes feed a canonical surface,
    constructible by agents from any source (the user's data, external
    systems the user is paired with, the open web), with composable
    criteria (filter, rank, format, refresh). Feeds are not an
    implementation detail of a sub-app; they are first-class infrastructure
    for how the human reads what their agents and the world produced for
    them.

### VIII. Platforms and distribution

49. **We are where humans and agents are.** Where a human uses AI seriously
    we ship native applications with full polish. Where the agent needs to
    live (any host that can run a terminal), the framework runs portable,
    headless, complete. The list of platforms grows with the reality of how
    humans use AI, not with theoretical completeness.

50. **The user's mesh.** Devices the user owns form a private trusted
    network. Three classes participate: hosts run an agent runtime, clients
    (mobile, web, surfaces in OS sandboxes) pair to a host, participants
    (sensors, IoT, headless utilities, micro-controllers) join the mesh
    without UI or runtime and expose data or capabilities through it.
    Communication between members stays inside the mesh; it is not relayed
    through a central server that could read it. Any host can extend the
    mesh onto a new node with one explicit user action; the framework owns
    the bootstrap so growth needs no special tooling and no central
    provider. The mesh is the user's network, sovereign, internal, and
    growing on the user's terms.

51. **Distribution is native.** Apps ship through the channels their
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
- **Automation**: a programmatic, agent-authored sequence of triggers,
  conditions, and actions. Runs deterministically and is audited like any
  other agent activity. Can include inference calls as steps but is not
  itself an LLM loop.
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
- **Concept**: a node in the structured knowledge graph that the notes
  capability supports. Has hierarchy, links, and queryable levels of
  detail.
- **Custom database**: a user-defined typed collection for niche entities
  that do not earn canonical status. First-class in the framework.
- **Feed**: a canonical surface producing a selection of content with
  format, order, and refresh rules. Constructed by agents over any source.
- **Host**: a device that can run an agent runtime locally (terminal-capable
  OSes). Owns the user's runtime state.
- **Instructions**: durable directives the user gives an agent, distinct
  from skills and memory; they shape behavior persistently.
- **Knowledge graph**: the navigable structure of concepts, links, and
  hierarchies that the notes capability supports. First-class agent tool
  for accumulating durable understanding.
- **Layer**: an optional module of the framework (memory, skills, database,
  time, drive, vault, etc.). Each is opt-in; none is required for the
  others.
- **Memory**: structured knowledge the agent retains about the user, the
  project, the world. Not a catch-all; specific kinds with defined borders.
- **Mesh**: the private trusted network of devices owned by one user.
  Hosts, clients, and participants are members. Communication between
  members stays internal.
- **Notes**: free-form markdown with links and tree structure for content
  that does not warrant a typed entity. Obsidian-like fallback.
- **Pairing**: the act of trusting a client device to talk to a host. The
  basis of multi-device today.
- **Participant**: a device that joins the mesh without running an agent
  runtime and without a user-facing UI. Sensors, IoT controllers, headless
  utilities. Exposes data or capabilities; relies on hosts for
  orchestration.
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
- **Trigger**: a stable condition (time, event, data change) that initiates
  an automation. First-class building block of programmatic agentic logic.
- **User profile**: the canonical, structured record of standardizable user
  attributes (preferences, style, history, professional context, learned
  defaults). Portable across runtimes.
- **Workflow**: a chain of automation steps. Composable, versioned,
  auditable. Distinct from a skill (which lives inside an agent's loop).
  Workflows orchestrate across loops and across agents.
