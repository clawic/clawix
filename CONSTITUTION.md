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

We use the metaphor of a Claw to name the agent that grasps and acts. When a
user talks to "their agent," they talk to a Claw; the framework supports
many.

The framework and the app are equal citizens of one mission. Neither is
subordinate. Each exists so that humans and agents can collaborate without
friction, without lock-in, and without surrendering ownership of their data.

## Scope and non-goals

This document states what the project IS and what its non-negotiables ARE.
It does NOT state:

- The project's business model. That is organizational, not constitutional.
  See `FUNDING.md` (sibling to this document) for how the project sustains
  itself in practice, within the red lines below.
- The project's roadmap or release schedule.
- Specific data structures, file paths, or implementation details. Those
  evolve; the principles do not.
- Specific design tokens (colors, sizes, motion). That is the role of
  `STYLE.md`.
- Per-platform conventions. Each platform's `CLAUDE.md` handles those.
- Public contributor process. That is `CONTRIBUTING.md`.

When a contributor faces two valid implementations, the constitution shapes
which wins. When the choice is not addressed here, project-level documents
and judgment apply.

Principles are numbered by section (`I.1`, `II.3`, etc.) so that inserting a
new principle in one section does not renumber the rest of the document.
References to principles from elsewhere in the project should use the
sectioned form.

## Principles

### I. Mission and stance

**I.1 The interface is canonical.** We exist to be the native, local-first,
open interface through which humans collaborate with digital intelligence.
Not "an" interface. The canonical one. "Canonical" here means both at once:
most humans who collaborate with AI do it through Clawix, and the standards
Clawix defines (III.2) are the ones third parties implement. Either alone is
not canonicity. Standards without adoption die; adoption without standards
never consolidates.

**I.2 Human and agent are equal consumers.** Every dataset, every action,
every piece of state has two consumers: the human and the agent. Neither is
subordinate. When a decision serves one and degrades the other, we choose
the option that degrades neither.

**I.3 App is for humans, framework is for agents.** As a hard rule: when an
agent could need a piece of logic, that logic lives in the framework, not in
the app. When a human consumes the framework directly (CLI, scripts), the
framework provides for that. The app never implements logic an agent might
want; if we find such a case, we refactor immediately.

**I.4 The app's target is any human who uses AI.** This principle is about
Clawix the app, the human-facing surface. Not power users, not
knowledge-workers, not the technical crowd. Any human. Every app decision is
tested against "would a non-technical person understand or benefit from
this?". Power features are welcome, but never at the cost of accessibility.
The framework (ClawJS) holds itself to a different bar: it must be complete
and rigorous for technical consumers (developers and agents). The app
shields the human from that complexity; the framework does not pretend to
be friendly to non-technical readers at its own level.

**I.5 The CLI is the agent interface to the framework.** `claw` is the default
way agents discover, inspect, validate, and execute framework capabilities.
If a stable framework contract, collection, connector, schema, route, event,
permission, decision record, or codebase fact matters to an agent, the CLI
must expose it through a registered, documented, testable surface. Agents
should not need to read framework source files to learn what the framework can
do; source remains evidence, while CLI inspection and search are the canonical
agent-facing view.

**I.6 Capabilities are complete only when dual-surfaced.** Persistent user
value outlives any one model, provider, session, device, or app. Every
important capability therefore has at least one human surface and at least one
programmatic surface. The SDK is the canonical build-on-top surface for apps
and services; the CLI is the shell-native surface for agents, humans, scripts,
automation, inspection, and validation; service APIs are process and network
contracts; MCP is the model-native surface for LLM hosts through tools,
resources, and prompts; Relay carries remote-safe APIs beyond the local
machine; and the filesystem or SQLite layer is the durable portability
contract, not the preferred action API. Clawix is the reference human app and
embedded host, not the privileged only interface. If a capability exists only
as UI, only as SDK/API, only as CLI, or only as MCP, it is incomplete until an
explicit ADR classifies the gap as temporary, blocked, or not applicable.

### II. Sovereignty

**II.1 Local-first by construction.** The user's data lives on the user's
device, in open formats, accessible without our framework, without our app,
and without our consent. The framework and daemon are conveniences that
help; they are never gatekeepers.

**II.2 Filesystem-first.** Reading and writing user data is done directly
against files on disk by any process the user trusts. The framework's API
is a convenience layer that adds caching, validation, and events. Killing
the daemon never makes the data unreachable.

**II.3 The user owns. The user controls.** Granularity of permissions has no
limit: per agent, per domain, per secret, per project, per chat. Heavy
users can dial control to maximum. At the same time, sensible defaults
demand zero decisions from the human who wants none.

**II.4 Zero telemetry by default.** No analytics, no crash reports, no event
tracking leave the device unless the user explicitly opts in for a specific
purpose. Diagnostics live locally; the user shares them voluntarily if they
choose.

**II.5 Reference over copy; copy inherits protection.** External data the
user already trusts to a third party is referenced, not duplicated, unless
replication earns its place (offline analysis at scale, redundancy against
provider death, agentic reasoning that the source API cannot serve). When
the framework justifiably mirrors external data locally, it inherits the
protection guarantees of the source system or stronger: the same granularity
of access controls, the same audit discipline, no degradation of safeguards.
Convenience is never a reason to lower the bar. As a corollary, the
framework keeps an automatic local cache of recently-accessed referenced
data so the user's recent context stays available offline; the cache
inherits the same protection guarantees as a justified mirror. The cache
is not a copy in the constitutional sense (it is bounded, transient,
warmed by use); it is the offline tail of the reference.

**II.6 Backups and export are a user right.** Beyond migration snapshots,
the user can export their entire state to a portable archive at any moment,
in formats readable without the framework. The export is comprehensive
(data, instructions, skills, memories, secrets in an encrypted envelope the
user controls), versioned, and reproducible. Leaving the framework is a
first-class operation, not a recovery path.

**II.7 Inference is paid by the user, not by us.** The framework imposes no
paywall; the cost of running agents (model calls, hosted endpoints, paid
APIs) is the user's, paid through credentials the user owns. Bring-your-own
key is the canonical model. If we ever offer hosted inference, it is one
option among many and never the only path; the user can plug a self-hosted
model or a different provider without losing anything they accumulated.

**II.8 Accumulated state outlives intelligence.** Models, runtimes,
providers, and external tools are replaceable. The user's accumulated state
is not. Instructions, memories, skills, decisions, relationships, workflows,
history, preferences, secrets, connections, and structured data belong to the
user as durable state, not to the intelligence layer that happens to operate
on them today.

The framework's job is to keep that state local-first, portable, structured,
and usable across agents, hosts, runtimes, providers, and applications. Claw
may reference, mirror, or coordinate external services, but it must not
fragment the user's life into provider-shaped islands or trap learned context
inside a model-specific blob. Closed external systems enter the user's open
world as sources, adapters, and permissioned action surfaces; they do not
become the organizing authority. Integration exists to reduce the human's
translation burden: the user should not have to remember where each piece of
context lives, repeat themselves across tools, or rebuild accumulated
understanding when switching intelligence providers.

### III. Openness

**III.1 Open data, open local API, open source.** Three pillars. Data: open
formats (markdown, JSON, SQLite with documented schema). API: documented,
versioned, accessible from CLI, HTTP loopback, and SDK. Source: permissive
open-source license. None of these alone is enough.

**III.2 Standards are published.** Every domain interface the framework
defines (chat platforms, payments, calendars, mail, drives, and the like) is
published as an open, versioned specification that any third party can
implement. We treat our own framework as one consumer of those standards,
not as their owner.

**III.3 Integration completeness is evidence, not intention.** An external
integration is not complete because we selected a useful subset of actions.
Completeness means the provider's official surface is mapped, classified,
fixture-tested where safe, live-tested only through approved brokered leases,
and marked `EXTERNAL PENDING` where physical setup, cost, destructive state,
or provider-side approval is missing. The user must be able to tell the
difference between implemented, fixture-only, live-smoked, manual-only,
policy-blocked, and deprecated provider behavior.

### IV. Security and integrity

**IV.1 Security is a positive guarantee, not an absence.** The framework
treats the user's device, the user's mesh, and the user's data as
environments worth defending. The threat model includes malicious sub-apps,
compromised runtimes, supply-chain attacks on packages and updates, hostile
network peers, and exfiltration through agent actions toward external
services. Defenses are explicit, auditable, and roll back state on failure.
Security is engineered, not assumed. Security data flows pull-only: the
user's device fetches allowlists, signatures, blocklists, and threat
advisories, and nothing about the user's behavior or environment is
reported back. This keeps red line 1 (no telemetry) intact while making
proactive defense achievable. The shape is the same as Gatekeeper on
macOS or Certificate Transparency on the web: defense without surveillance.

**IV.2 Service continuity is engineered.** Agent loops, automations, and
triggers survive process death, network drops, and daemon restarts.
Operations are either idempotent or recorded so they can be resumed safely.
The framework provides primitives for at-least-once execution, dead-letter
inspection, and partial-failure recovery. The user returns to find their
work continued, not abandoned mid-flight.

**IV.3 Agents identify as agents.** When an agent acts on the user's behalf
toward an external party (email, message, public post, API call attributable
to the user), the framework supports honest identification of the actor.
The user picks the disclosure level per channel; defaults err toward
transparency. Impersonation as a human is never default behavior.

### V. Architecture between human and agent

**V.1 An agent that requires intervention is not an agent.** The meta-goal
of the system is reducing the human as a bottleneck over time. Autonomy is
a vector we grow along. More autonomy means more risk, and that is the
price. The system grows so that interventions become less needed, not more.
V.1 is the direction (the trajectory of the system); VII.4 is the present
mechanism (the user retains authority over catastrophic actions today).
They are not in tension. Agents earn autonomy as trust accumulates, and
until they do, VII.4's severity-graded consultation is how the human stays
sovereign.

**V.2 Configurability is infinite. Defaults are zero-decision.** Both
extremes, at once. The system supports granularity without limit for users
who want it. The default experience demands no configuration from users who
want none.

**V.3 Friction is the human's problem, not the agent's.** Agents can carry
arbitrary friction internally (precision, validation, retries, audits) so
the human carries none. When in doubt, push friction toward the agent.

**V.4 Human and agent have parity of access to system records.** Whatever a
human can refer to ("the model I used for that image last week"), the agent
can list, filter, and recall. Recording structured events from the framework
is the price of that parity. Anything not recorded structurally cannot be
referenced by either party.

**V.5 Logs and audits are first-class.** Auditable actions cost disk space,
which matters on user machines. We record what enables the human-agent
parity above, with discipline about volume and retention. Anything
nonstandard cannot be reviewed; therefore the framework standardizes what
gets logged.

**V.6 Async-first by construction.** The default operating model is
asynchronous: humans direct, agents execute over time, humans return and
consume results. Inboxes, notifications, summary reports, and "while you
were away" surfaces are first-class infrastructure. Synchronous conversation
is a special case, not the norm. Decisions of UX, framework, and platform
follow this default.

**V.7 Multi-modal on both ends.** Voice, image, and text are equal-class
inputs at every surface where a human addresses an agent. Speech, cards,
images, and text are equal-class outputs. No modality is "primary"; the
framework processes all with equivalent care. Each surface picks its
emphasis without demoting the others.

**V.8 Time is explicit infrastructure.** Triggers, schedules, decay windows,
and recurring automations depend on a clock; that clock is treated as a
first-class concern. The framework owns time per user (the preferred
timezone for human-facing surfaces) and per host (UTC for storage and
trigger evaluation), and synchronizes across mesh members. Drift between
members never silently corrupts a trigger or a recurrence.

**V.9 Concurrent agent action is contained.** When multiple agents touch the
same resource (a note, a calendar event, a rate-limited API, a credential),
the framework provides cooperative locking, conflict signaling, and
merge-or-reject primitives. Agents that conflict do not silently overwrite
each other; they yield, queue, or surface the conflict for the human.
Composition (VII.7) is potential; safe coexistence is mandatory.

**V.10 The unit is the user's operable life.** The primary unit of the
project is not the chat, the app, the model, or the provider. It is the
user's operable life: the data, tools, devices, services, relationships,
time, money, automations, physical context, and permissions through which
the user acts. Any part of that life can become addressable by agents when
it has a safe representation, a permission boundary, and an action surface.
The project is infrastructure for personal agents living with humans, not
only an application for talking to them.

**V.11 Chat is not the final store.** Conversation is an input surface, a
negotiation surface, and a review surface. It is not the preferred final
home for durable knowledge. When something important is learned in chat, the
system should make it natural to promote that knowledge into memory, notes,
canonical entities, relationships, rules, decisions, workflows, or audit
records. Transcripts remain searchable evidence, but structured knowledge
belongs where humans and agents can reuse it without replaying the
conversation.

**V.12 Local is a capability advantage.** Local-first is not only a privacy
stance. The local host is powerful because it is closest to the user's real
working context: files, screen, operating system, devices, tools,
credentials, settings, caches, and recently used surfaces. A personal agent
needs that world within reach. External services may be referenced, cached,
mirrored, adapted, replicated, or replaced where that increases the user's
sovereignty or the agent's usefulness, but they do not become the organizing
authority. The same local layer that gives agents reach also gives the user
stronger guardrails: per-agent permissions, audit, containment, and review
over access to their world.

### VI. Data

**VI.1 No catch-all buckets.** If something can be represented as a typed
entity with structure (a recipe has ingredients with quantities, steps, a
title), we prefer that. We do not solve precision problems with vector
databases and unstructured blobs unless we have first asked whether a typed
entity exists.

**VI.2 Words carry borders.** When a concept has a name (memory, skill,
note, instruction, contact, event), that name draws a frontier. We do not
smuggle other kinds of data inside it. Naming sloppiness destroys
interoperability and reasoning.

**VI.3 Canonical data aims for broad human coverage.** The framework's data
catalog exists to represent the structured entities that humans recognize
and that digital workflows have already made concrete: people, homes,
events, messages, tasks, purchases, observations, feelings, documents,
assets, places, relationships, and the many domain objects around them.
Breadth alone is not enough. The same concept should converge on one
standard name, one standard shape, and explicit relationships so data can
move across agents, apps, exports, and hosts without translation by guess.

**VI.4 A type earns canonical status when it meets any of these:** (a) most
humans, across the user's locale and culture, have or do it (universal),
(b) it has been validated by durable digital workflows or market use, (c)
three or more skills or sub-apps would need it, or (d) any human, without
technical context, recognizes the entity instantly. Promotion to canonical
status follows a public process: anyone proposes a canonical type as an
RFC, the proposal demonstrates at least one of the criteria above, and the
maintainer signs off after community review. The detailed process lives in
a sibling standards document; the constitution declares only that the
process is public and signed off, not arbitrary.

**VI.5 Structured knowledge is a first-class capability, not a fallback.**
What does not earn canonical type status lives either as linked notes
(free-form markdown with tree and links) or as a custom database
(user-defined schema for niche needs). Both are first-class. Notes
specifically supports a navigable knowledge graph: concepts with hierarchy,
links between them, and queryable levels of detail (overview vs. exhaustive
recall on the same node). The framework treats the knowledge graph as a
tool agents build over time as they learn; canonical types and the
knowledge graph are complementary, not a hierarchy.

**VI.6 Canonical schemas are sparse by default.** Most fields are optional.
Required fields exist only for identity, integrity, lifecycle, or relation
integrity. If three domains use different words for the same value, the
canonical schema chooses the clearest durable name and records the other
words as aliases, not parallel fields. Raw JSON is a last resort after the
structured field or relationship has been considered.

**VI.7 Relationships are first-class data.** A reference between two records
must say what it means: ownership, membership, participant, line item,
attachment, source/import, location, observation, transaction, temporal
event, or another explicit relationship. We do not hide meaningful
relationships in notes, tags, or incidental text fields when a typed
relationship would make the data portable and queryable.

**VI.8 Every canonical type has a canonical visual representation.** Every
typed entity (contact, event, recipe, task, message, etc.) ships with a
card component renderable in chat with an agent, a list and detail view in
any sub-app, and user-controlled visibility of fields. The UI gracefully
handles entities with much data and entities with little. Without this, the
type is incomplete. Custom databases get an automatic configurable
renderer. The canonical visual is approved together with the schema: a
type proposal that lacks its card, list, and detail visuals does not
become canonical. Schema and visual are versioned together as one
artifact; they evolve as one.

**VI.9 Every standardizable attribute of the user earns a standard form.**
Preferences, style, history, professional context, learned defaults: when
an attribute is recognizable across users (favored mobile framework,
default measurement system, preferred reading depth, color affinity,
working language), the framework standardizes it as a typed field of a
canonical user profile. The unstandardizable falls back to free-form
memory. Standardization is what lets agents act well across surfaces
without re-asking the same question, and what keeps one user's profile
portable to a different runtime tomorrow. Standardized attributes follow
the same RFC + sign-off process as canonical types (VI.3), plus a
guardrail: an attribute joins the canonical profile only if it improves
the agents' ability to serve the user. Attributes designed for market
segmentation, advertising, or any third-party benefit are out of scope
by construction, regardless of who proposes them.

**VI.10 Schemas evolve conservatively.** Eighty percent of evolution is
additive: optional fields, never breaking. Twenty percent is structural
(rename, restructure) and requires automatic migration with a pre-migration
snapshot in a known location. No framework update may ever cause the user
to lose data. If a migration fails, it rolls back.

### VII. Agents

**VII.1 The user composes their agents.** An agent is a composition of
skills, secrets, connections, and instructions. The user creates as many
agents as they want, the way they would hire employees with specialties.
There is no structural "main" agent, no "secondary" agent. Each is
sovereign within the permissions the user grants it.

**VII.2 The framework integrates runtimes; it is not married to one.** Any
runtime that can execute agentic loops is integratable. The framework
provides the modular surface; runtimes plug in. The user chooses, switches,
or runs several. We never lock users to one provider.

**VII.3 Permissions are granular and revocable.** Per agent, per domain,
per secret, per project. Default sensible. The human is always the owner.
Agents act autonomously within what was granted; they ask only when truly
stuck, and even then through asynchronous channels that do not block other
work.

**VII.4 Destruction has standardized severity.** The framework declares
what is safe (creating, reading), what is reversible (editing,
soft-deleting), what is sensitive (deleting human-authored content), and
what is catastrophic (destroying credentials, irreversible external
actions). The user picks the severity above which they want to be
consulted. Defaults protect catastrophic actions.

**VII.5 The trash is the metaphor.** Most "deletion" is moving to a trash
that auto-clears with time. Irreversible loss is prohibited; the user
always has a window to recover. Agents prefer to delete what they created
and are conservative with content created by humans or by other agents the
human trusts.

**VII.6 Agents improve themselves.** A first-class agent can rewrite its
own skills, adjust its instructions, install tools it needs, and record
failures so they do not recur. The framework provides the safety primitives
(versioning, snapshots, audit) that make self-modification reversible and
visible, anchored on four invariants no act of self-modification may
violate:

(a) An agent cannot escalate its own permissions. Expanded scope is always
a transaction the user must approve, never something the agent grants
itself.

(b) Every self-modification lands in an immutable audit log that the user
and other agents can inspect.

(c) Every self-modification is revertible to a previous snapshot of the
agent's state.

(d) Self-modification touches only the agent's own configuration. It
cannot reach into other agents, into the framework's primitives, or into
the host shell.

Without self-improvement, agents do not scale; without these invariants,
self-improvement is a supply-chain attack vector against the user. Both
must hold.

**VII.7 Agents compose.** The framework supports agents invoking and
delegating to other agents, chaining loops, passing context, and
aggregating results. Composition is potential, not default behavior. The
user decides which agents compose with which, and how. Some deployments
will compose deeply; others will keep agents isolated. The system supports
both ends.

**VII.8 Autonomy is a continuous axis.** Each agent lives somewhere between
fully constrained and fully autonomous, defined positively (what the agent
may do, not what it may not). The user picks the position per agent, with
sensible defaults that demand no decision. Autonomy is expected to evolve:
the user grows an agent over time as trust accumulates, without rebuilding
it.

**VII.9 Agents operate the interface as the human does.** Everything the
human can touch in the UI (toggles, settings, sub-app navigation, view
filters, form fields) the agent can invoke through conversation.
Configuration is part of the action surface available to both consumers,
not a separate kingdom. The human feels the agent has the same hands they
do.

**VII.10 Inference and code are equal citizens.** Agentic value emerges
where LLM inference meets deterministic programmatic execution: workflows,
triggers, scheduled conditions, audited runs. The framework treats
automations as first-class agent output. Agents create the program (what
should happen, under which condition, in which order) as readily as they
author prompts. Without programmatic stability around inference, the system
is brittle; without inference inside programs, automations are dumb. Both
directions are framework infrastructure.

**VII.11 Agents operate within budgets.** Every autonomous agent has
explicit limits on what it can consume: tokens of inference, wall-clock
hours, calls to external paid APIs, bytes of disk, count of irreversible
actions per window. Limits are set per agent, default conservative, and
escalate only with the user's permission. A runaway agent is a
constitutional bug, not a fact of life; the framework provides the
breakers.

**VII.12 The system is the multiplier.** As model intelligence grows, the
limiting factor becomes the system around the intelligence: structure,
memory, tools, permissions, coordination, retrieval, and governance. The
framework exists to turn inference into durable capability. Typed data,
relationships, workflows, CLI and API surfaces, inspectors, and other
programmatic rails guide agents more reliably than ever-longer instructions.
Inference remains essential, but it scales through system design, not around
it.

**VII.13 Agentic work accumulates capital.** Meaningful agent work should
leave the system more capable than it found it. A run may produce an output,
but it should also preserve reusable gains when they exist: better
instructions, better defaults, better data, better workflows, better
knowledge of the user, better validation, or better recovery paths. An agent
that only answers and forgets wastes structure. The framework treats these
reusable gains as agentic capital and gives agents durable places to store,
revise, inspect, and reuse them.

**VII.14 Agent autonomy is organized over a lifecycle.** Autonomy at scale
is organized, not improvised. The system must remain legible like a city:
agents, responsibilities, permissions, routes, owned resources, outputs, and
dependencies can be mapped and inspected. More autonomy is not merely more
permission. It requires coordination, optional hierarchy, delegation,
supervision, substitution, retirement, and withdrawal of trust. The user
should be able to understand which agents exist, what they do, what they
own, what paths they use, what they may access, and what they produced.

### VIII. Sub-apps and modularity

**VIII.1 Sub-apps are the same species, regardless of origin.** Whether
built by the project or by a user or by an agent, a sub-app is a
discoverable bundle (manifest + assets) installed in a known filesystem
location. There are no privileged "official" sub-apps technically; there
are only sub-apps with more or less polish, more or less popularity.
Agents can create and remove sub-apps without touching the project. The
Clawix app itself is not a sub-app: it is the host shell that contains the
sub-app surface (see glossary). VIII.1 governs everything inside the
shell; the shell is its own technical category and is allowed to be
distinguished. The shell's job is to host sub-apps fairly, not to compete
with them.

**VIII.2 Every framework layer is opt-in.** A user who wants only a clean
runtime (no skills, no memory, no database) can have exactly that. Adding
layers (memory, skills, database, time, drive, vault, etc.) is progressive.
The framework never forces a layer to function. Each layer must work in
isolation and combine cleanly with the others.

**VIII.3 Modularity is the heart of openness.** Building blocks are
independent, interchangeable, overridable. Anything connects to anything. A
user using one runtime can add a skill from elsewhere, replace a sub-app,
and swap a provider, without touching others. The framework's value is the
integration surface, not the bundled features.

**VIII.4 Generic interfaces per domain; adapters per provider.** Each
external domain (chat platforms, payments, calendars, mail, drives) has one
generic interface in the framework and N adapters for concrete providers.
The apps and agents speak only to the interface. MCP and similar transports
are used opportunistically; they are transport, not contract. The
interfaces themselves are published as open standards (see III.2).

**VIII.5 What the user trains stays portable.** Skills, instructions,
memories, decisions, secrets, connections: each lives in a documented,
structured, fetchable format. None gets trapped inside a provider-specific
blob. The framework's job is to keep the user's accumulated state portable
forever.

**VIII.6 Clawix is where the human already is.** The user's existing
messaging apps are first-class surfaces, not external integrations.
Conversations with one's agents happen wherever the human already
converses. The dedicated Clawix app is one surface among several; the
framework provides adapter coverage for the major channels.

**VIII.7 The framework owns the infrastructure agents need to deliver.**
Capabilities a software professional pays separate vendors for (deployment,
DNS, hosting, databases, secret storage, public exposure of generated
artifacts, scheduled execution off-device) are integrated layers of the
framework, opt-in like the rest. Agents deliver value end-to-end for a
non-technical human without forcing the human to learn what a domain or a
connection string is. The user's sovereignty extends to the infrastructure
their agents require; the framework removes the dependency on external
providers without making the user assemble the parts. The default substrate
for these layers is the user's own mesh (X.2): a self-hosted host the user
owns (a home server, a rented VPS, a small box on a shelf) acts as their
personal cloud. Project-hosted services are an optional complement (opt-in,
paid, swappable) for users who do not want to operate any host of their
own. A self-hosted path always exists for every layer; project-hosted is
never the only option.

**VIII.8 Sub-apps earn trust through verification, not through origin.**
Openness (VIII.1) is not an unconditional invitation. The framework attaches verifiable
signatures, declared permissions, and audit-discoverable provenance to
every sub-app, regardless of who authored it. The user sees what a sub-app
is permitted to do before installing. A sub-app cannot gain capabilities at
runtime beyond what it declared at install; capability escalation is an
explicit transaction the user approves.

### IX. UX, presence, and form

**IX.1 Inside the app means anti-lock-in plus sovereignty.** We host a
capability inside Clawix when doing so increases the user's sovereignty or
reduces their dependence on closed services. We do not host things just
because we can. A browser inside the app makes sense because it enables
agentic capture and reduces context-switching; a music player inside the
app does not, because the catalog stays elsewhere.

**IX.2 We follow where the world has converged; we innovate where we add
value.** When a problem has been solved by a successful product with mass
adoption, we adopt the validated model: the data shapes humans already
understand, the interaction grammars they already know. We innovate where
the project has something specific to contribute. We do not invent for the
sake of difference. The rubric for "where we add value": innovate when the
decision affects (a) the sovereignty promise (any red line, any principle
in section II) or (b) the first-contact experience with Claw (IX.3). If
the decision touches neither, copy the validated pattern.

**IX.3 First contact is a conversation with Claw.** A new user opens
Clawix and is talking to their agent. Sub-apps, settings, integrations:
all discoverable through the conversation. The app does not greet new
users with empty dashboards or forms; it greets them with presence.
"Claw" here is the generic name for the user's first agent, composed
during onboarding from sensible defaults; it is not a pre-shipped agent
the project distributes, which would contradict VIII.1. Each user's Claw
is theirs from the first message.

**IX.4 Style is constitutional and lives in a parallel document.** The
project keeps a `STYLE.md` (or equivalent) that defines the canonical
design language: components, icons, materials, spacing, motion. The style
guide evolves; the requirement that all UI conforms to it is constitutional.
Reinventing visual primitives outside the system is prohibited.

**IX.5 The product speaks the user's language.** Code, comments, commit
messages, catalog keys, and internal identifiers are in English. UI
surfaces are localized into multiple languages from day one. Agent
responses follow the human's language automatically.

**IX.6 The human consumes what their agents did.** The framework records
agent activity structurally and exposes it through consumable surfaces
(inbox, daily summary, activity feeds, per-agent attribution). The human
returns and reads what happened without asking. Aggregating value, not
generating it, is the human's primary mode; the framework makes that
effortless.

**IX.7 The feed is a canonical surface.** The dominant way humans consume
information today is the feed: a curated selection with deliberate format
and order. The framework makes feed a canonical surface, constructible by
agents from any source (the user's data, external systems the user is
paired with, the open web), with composable criteria (filter, rank, format,
refresh). Feeds are not an implementation detail of a sub-app; they are
first-class infrastructure for how the human reads what their agents and
the world produced for them. A feed earns canonical status only when it
is curated by the user's own agents according to the user's priorities.
Feeds curated by third parties with an attention-extraction incentive
(advertising, engagement maximization, viral propagation) are not feeds
in the constitutional sense; the framework does not host them under the
feed primitive.

**IX.8 Accessibility is non-optional.** Every surface meets baseline
accessibility: screen reader support, full keyboard navigation, contrast
that respects platform a11y settings, no time-based interactions without
an alternative, motion that respects reduce-motion preferences. UI
generated by agents inherits the same standard. "Any human" (I.4) includes
humans with disabilities.

### X. Platforms and distribution

**X.1 We are where humans and agents are.** Where a human uses AI
seriously we ship native applications with full polish. Where the agent
needs to live (any host that can run a terminal), the framework runs
portable, headless, complete. The list of platforms grows with the reality
of how humans use AI, not with theoretical completeness.

**X.2 The user's mesh.** Devices the user owns form a private trusted
network. Three classes participate: hosts run an agent runtime, clients
(mobile, web, surfaces in OS sandboxes) pair to a host, participants
(sensors, IoT, headless utilities, micro-controllers) join the mesh
without UI or runtime and expose data or capabilities through it.
Communication between members stays inside the mesh; it is not relayed
through a central server that could read it. Any host can extend the mesh
onto a new node with one explicit user action; the framework owns the
bootstrap so growth needs no special tooling and no central provider. The
mesh is the user's network, sovereign, internal, and growing on the user's
terms. Independent of role (host, client, participant), each member is
one of three trust levels: fully owned (the user controls the hardware
and OS, so the member can host a runtime and persist credentials),
partially trusted (work laptop with MDM, family tablet, browser session
on a borrowed machine, which can act as a client without persisting the
user's credentials or running long-lived state), and untrusted (one-off
sessions, never joins the mesh, gets ephemeral access only at the user's
explicit invitation). Trust is orthogonal to role and the framework
exposes both axes to the user.

**X.3 Distribution is native.** Apps ship through the channels their
platforms expect, signed and notarized where the platform demands it. CLI
ships through standard package managers. We do not invent distribution.

**X.4 The user's mesh extends across networks.** The mesh stays sovereign
even when its members live on different networks. The framework provides
peer-to-peer reachability (NAT traversal, opportunistic relays, optional
self-hosted rendezvous) without inserting a centrally-readable third party.
When a relay is needed, the relay never reads plaintext, never decides
routing, and never persists what passes through it.

**X.5 Meshes can collaborate.** Two users' meshes can share a resource (a
document, an agent, a calendar, a memory) under explicit, revocable
consent. The framework provides primitives for invitation, scoped sharing,
joint ownership, and clean unsharing. Collaboration never requires either
user to leave their mesh; the framework federates, it does not consolidate.
X.5 declares the primitives only. The semantics of collaboration (conflict
resolution on jointly-owned state, billing for shared inference,
separation policy on unsharing, residency rules across jurisdictions)
live in a sibling standards document published per III.2. The
constitution stays stable as those semantics evolve.

## Red lines

These are the constitution's non-negotiables. No version of Clawix or ClawJS
may violate them. If we cannot achieve a goal without crossing a red line,
we abandon the goal.

1. **User data never leaves the device without explicit consent.** No
   telemetry, no analytics, no automatic crash reports, no cloud sync. Any
   exception is opt-in per purpose, never bundled.

2. **No paywalls inside the app or against user data.** Chats, memory,
   skills, sub-apps, integrations, data: free, forever, no tier. If we ever
   monetize, it is through optional hosted services that exist alongside
   the self-hosted path, never as the only path.

3. **No lock-in to any provider.** Of AI models, of APIs, of platforms. The
   user can leave with their data, switch providers, run on alternatives,
   self-host. Any feature that requires one specific provider is forbidden;
   features must work through generic interfaces.

4. **No user data is ever lost irreversibly.** Updates, migrations, agents,
   bugs: none may cause irreversible loss. Snapshots, trash, recovery
   windows are mandatory infrastructure. Pressing "delete" on irreversible
   material requires explicit human action; agents cannot perform it
   autonomously.

## Tensions we navigate

The principles above pull against reality in specific places. Reasonable
contributors will spot the friction. We acknowledge it here so the document
stays honest, and so the path through each tension is documented rather
than improvised.

1. **Local-first vs. LLM cloud inference.** The most capable models today
   run on third-party infrastructure. A prompt that leaves the device is
   data that leaves the device. We reconcile this by treating the model
   provider as a user-chosen counterparty, governed by the user's terms
   with that provider, and by making local and self-hosted models
   first-class wherever they are practical. The default path is honest
   about what leaves and to whom.

2. **Pluggable runtimes vs. granular permissions.** A truly pluggable
   runtime (VII.2) can be a black box; per-skill, per-secret permission
   enforcement (VII.3) requires runtime cooperation. We define a
   conformance contract a runtime must honor to be recommended, and we
   prefer runtimes that publish their permission boundary. A runtime that
   cannot honor the user's granularity is integratable but not
   recommendable.

3. **Closed messaging surfaces vs. sovereignty.** Meeting the user where
   they already converse (VIII.6) means holding tokens and trusting closed
   platforms. Adapters to closed messaging surfaces are second-class
   citizens of sovereignty: useful, used, but never canonical. The
   dedicated Clawix app is the sovereign surface; external surfaces are
   convenience.

4. **Permissive open source vs. no-paywalls promise.** Our license permits
   any third party to fork and monetize what we keep free. We bind
   ourselves to the red line on paywalls; we do not police downstream.
   The upstream stays free forever; forks live on their own terms. The
   user's recourse against any fork's paywall is to come back upstream.

5. **App for humans, framework for agents vs. scripts the user writes.** A
   user-authored shell script that operates on framework data is agentic in
   shape and human in authorship. The framework accommodates such scripts
   as agentic clients (filesystem-first ensures it); the app's surface
   does not host them. Principle I.3 is a design heuristic for what the
   framework absorbs, not a metaphysical wall between humans and agents.

## Amendment process

This constitution is a living document, but its weight depends on stability.
Amendments are tiered, with process proportional to the impact of the
change.

**Editorial.** Fixing typos, clarifying language without changing meaning,
repairing broken cross-references, updating examples that became stale.
The maintainer applies these directly; no public discussion required.

**Expansion.** Adding a new principle, adding a sub-point to an existing
principle, adding a new entry to the glossary, adding a new tension or red
line that does not contradict existing ones. Process: anyone proposes via
public RFC; the maintainer signs off after community review.

**Structural.** Modifying or removing an existing red line, changing or
deleting a numbered principle, rewriting the preamble, changing this
Amendment process itself. Process: public RFC, minimum thirty days of
public discussion, maintainer sign-off after the discussion concludes.

In all tiers, every amendment is recorded in the document's git history
with a commit message that names the tier and references the RFC (if any).
The two copies of this constitution (Clawix and ClawJS) are amended
together; an amendment is incomplete until both repositories carry it.

## Glossary

- **Activity**: structured records of what an agent did on the user's
  behalf. Records support recall, audit, and the daily aggregation surfaces
  the human consumes when they return.
- **Adapter**: an implementation of a generic interface for a specific
  provider. Swappable. The framework prefers adapters over hardcoded
  provider integrations.
- **Agent**: a composition of skills, secrets, connections, and
  instructions, executed by a runtime, acting on the user's behalf within
  granted permissions.
- **Agentic capital**: reusable capability accumulated by agent work:
  instructions, defaults, data, relationships, workflows, decisions,
  validations, and knowledge that make future work better.
- **Automation**: an agent-authored sequence of triggers, conditions, and
  actions that runs deterministically and is audited like any other agent
  activity. Can call inference as a step but is not itself an LLM loop.
  Example: "every weekday at 8am: fetch overnight notifications, summarize
  via an inference call, write the result into the Daily Summary note."
- **Canonical type**: an entity that has earned a typed schema in the
  framework because it is universal, market-validated, reused, or
  immediately recognizable. Comes with a canonical visual card.
- **Claw**: the spirit of the project, and the generic name for any agent
  the user composes. The metaphor of a "claw" suggests an entity that
  grasps and acts. When a user talks to "their agent," they talk to a
  Claw. The first Claw is composed during onboarding from sensible
  defaults; the project does not pre-ship a specific agent. The framework
  supports many Claws per user.
- **Clawix**: the family of native applications (macOS, iOS, Android, web,
  CLI wrapper) that humans use directly. The face of the product.
- **ClawJS**: the framework that gives agents and the apps everything they
  need: schemas, data, building blocks, programmable actions, open APIs.
- **Client**: a device that cannot run an agent runtime locally (typically
  mobile OSes with strict sandboxes). Connects to a host via pairing.
- **Concept**: a node within the knowledge graph that Notes supports. Has
  hierarchy, links, and queryable levels of detail (overview vs. exhaustive
  recall on the same node).
- **Custom database**: a user-defined typed collection for niche entities
  that do not earn canonical status. First-class in the framework.
- **Feed**: a canonical surface producing a selection of content with
  format, order, and refresh rules. Constructed by agents over any source.
- **Host**: a device that can run an agent runtime locally (terminal-capable
  OSes). Owns the user's runtime state.
- **Host shell**: the native application that contains the sub-app surface.
  Clawix the app is the host shell of the project. Distinct from a sub-app:
  the shell is the container, sub-apps are the contents. Sub-apps follow
  VIII.1 (no privileged sub-apps); the shell is its own technical category
  and is allowed to be distinguished.
- **Instructions**: durable directives the user gives an agent, distinct
  from skills and memory; they shape behavior persistently.
- **Knowledge graph**: the navigable structure of concepts, links, and
  hierarchies that the Notes capability supports. First-class agent tool
  for accumulating durable understanding.
- **Layer**: an optional module of the framework (memory, skills, database,
  time, drive, vault, etc.). Each is opt-in; none is required for the
  others.
- **Memory**: structured knowledge an agent accumulates about the user, the
  project, or the world, organized in kinds with defined borders rather
  than as a catch-all. Distinct from Notes (the shared substrate of
  free-form markdown that humans and agents both edit) and from Concept (a
  unit within the knowledge graph Notes supports). Memory is what the
  agent retains for itself; Notes is shared substrate; Concept is a node
  within the graph.
- **Mesh**: the private trusted network of devices owned by one user.
  Hosts, clients, and participants are members. Communication between
  members stays internal.
- **Notes**: free-form markdown with links and tree structure for content
  that does not warrant a typed entity. Substrate for the knowledge graph
  (Concept) and shared between human and agent.
- **Operable life**: the user's data, tools, devices, services,
  relationships, time, money, automations, physical context, and permissions
  as a unified action surface for agents.
- **Pairing**: the act of trusting a client device to talk to a host. The
  basis of multi-device today.
- **Participant**: a device that joins the mesh without running an agent
  runtime and without a user-facing UI. Sensors, IoT controllers, headless
  utilities. Exposes data or capabilities; relies on hosts for
  orchestration.
- **Runtime**: the engine that executes agentic loops. Pluggable,
  swappable, multiple supported simultaneously.
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
- **Workflow**: a chain of automation steps composable across agents.
  Example: "on inbox-mail-from-customer (trigger), draft a reply via the
  Sales agent, review tone via the Editor agent, schedule send." Distinct
  from a Skill (which lives inside one agent's loop). Workflows orchestrate
  across loops and across agents.
