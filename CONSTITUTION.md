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
Not "an" interface. The canonical one.

**I.2 Human and agent are equal consumers.** Every dataset, every action,
every piece of state has two consumers: the human and the agent. Neither is
subordinate. When a decision serves one and degrades the other, we choose
the option that degrades neither.

**I.3 App is for humans, framework is for agents.** As a hard rule: when an
agent could need a piece of logic, that logic lives in the framework, not in
the app. When a human consumes the framework directly (CLI, scripts), the
framework provides for that. The app never implements logic an agent might
want; if we find such a case, we refactor immediately.

**I.4 The target is any human who uses AI.** Not power users, not
knowledge-workers, not the technical crowd. Any human. Every decision is
tested against "would a non-technical person understand or benefit from
this?". Power features are welcome, but never at the cost of accessibility.

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
Convenience is never a reason to lower the bar.

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

### IV. Security and integrity

**IV.1 Security is a positive guarantee, not an absence.** The framework
treats the user's device, the user's mesh, and the user's data as
environments worth defending. The threat model includes malicious sub-apps,
compromised runtimes, supply-chain attacks on packages and updates, hostile
network peers, and exfiltration through agent actions toward external
services. Defenses are explicit, auditable, and roll back state on failure.
Security is engineered, not assumed.

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

**VI.3 A type earns canonical status when it meets any of these:** (a) most
humans, across the user's locale and culture, have or do it (universal),
(b) it has been validated by markets (a dedicated app or SaaS with mass
adoption already exists), (c) three or more skills or sub-apps would need
it, or (d) any human, without technical context, recognizes the entity
instantly.

**VI.4 Structured knowledge is a first-class capability, not a fallback.**
What does not earn canonical type status lives either as linked notes
(free-form markdown with tree and links) or as a custom database
(user-defined schema for niche needs). Both are first-class. Notes
specifically supports a navigable knowledge graph: concepts with hierarchy,
links between them, and queryable levels of detail (overview vs. exhaustive
recall on the same node). The framework treats the knowledge graph as a
tool agents build over time as they learn; canonical types and the
knowledge graph are complementary, not a hierarchy.

**VI.5 Every canonical type has a canonical visual representation.** Every
typed entity (contact, event, recipe, task, message, etc.) ships with a
card component renderable in chat with an agent, a list and detail view in
any sub-app, and user-controlled visibility of fields. The UI gracefully
handles entities with much data and entities with little. Without this, the
type is incomplete. Custom databases get an automatic configurable
renderer.

**VI.6 Every standardizable attribute of the user earns a standard form.**
Preferences, style, history, professional context, learned defaults: when
an attribute is recognizable across users (favored mobile framework,
default measurement system, preferred reading depth, color affinity,
working language), the framework standardizes it as a typed field of a
canonical user profile. The unstandardizable falls back to free-form
memory. Standardization is what lets agents act well across surfaces
without re-asking the same question, and what keeps one user's profile
portable to a different runtime tomorrow.

**VI.7 Schemas evolve conservatively.** Eighty percent of evolution is
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
visible. Without self-improvement, agents do not scale.

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

### VIII. Sub-apps and modularity

**VIII.1 Sub-apps are the same species, regardless of origin.** Whether
built by the project or by a user or by an agent, a sub-app is a
discoverable bundle (manifest + assets) installed in a known filesystem
location. There are no privileged "official" sub-apps technically; there
are only sub-apps with more or less polish, more or less popularity.
Agents can create and remove sub-apps without touching the project.

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
providers without making the user assemble the parts.

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
sake of difference.

**IX.3 First contact is a conversation with Claw.** A new user opens
Clawix and is talking to their agent. Sub-apps, settings, integrations:
all discoverable through the conversation. The app does not greet new
users with empty dashboards or forms; it greets them with presence.

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
the world produced for them.

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
terms.

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

4. **No user data is ever lost.** Updates, migrations, agents, bugs: none
   may cause irreversible loss. Snapshots, trash, recovery windows are
   mandatory infrastructure. Pressing "delete" on irreversible material
   requires explicit human action; agents cannot perform it autonomously.

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
- **Automation**: an agent-authored sequence of triggers, conditions, and
  actions that runs deterministically and is audited like any other agent
  activity. Can call inference as a step but is not itself an LLM loop.
  Example: "every weekday at 8am: fetch overnight notifications, summarize
  via an inference call, write the result into the Daily Summary note."
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
- **Concept**: a node within the knowledge graph that Notes supports. Has
  hierarchy, links, and queryable levels of detail (overview vs. exhaustive
  recall on the same node).
- **Custom database**: a user-defined typed collection for niche entities
  that do not earn canonical status. First-class in the framework.
- **Feed**: a canonical surface producing a selection of content with
  format, order, and refresh rules. Constructed by agents over any source.
- **Host**: a device that can run an agent runtime locally (terminal-capable
  OSes). Owns the user's runtime state.
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
