import SwiftUI
import Combine
import AppKit
import ClawixCore
import ClawixEngine

extension Notification.Name {
    static let clawixOpenURL = Notification.Name("clawix.openURL")
}

enum ClawixDeepLink: Equatable {
    case session(String)
    case authCallback(provider: String)

    static func parse(_ url: URL) -> ClawixDeepLink? {
        guard url.scheme?.lowercased() == "clawix" else { return nil }
        guard let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        switch host {
        case "session":
            guard parts.count == 1 else { return nil }
            return .session(parts[0])
        case "auth":
            guard parts.count == 2, parts[0].lowercased() == "callback" else { return nil }
            return .authCallback(provider: parts[1])
        default:
            return nil
        }
    }
}

enum SidebarRoute: Equatable {
    case home
    case search
    case plugins
    case automations
    case project
    /// Apps surface routes. `.app(id)` opens one mini-app in the
    /// center pane (full-bleed, no browser chrome); `.appsHome` is
    /// the catalog grid the sidebar Apps header points at.
    case app(UUID)
    case appsHome
    case chat(UUID)
    case settings
    case secretsHome
    /// Database admin (3-pane explorer over all collections).
    case databaseHome
    /// External database workbench shell for connection profiles, SQL drafts, and result workflow.
    case databaseWorkbench
    /// Curated entry pointing at a single collection. Renders the same
    /// adaptive UI as `.databaseHome` but filtered + with curated tabs.
    case databaseCollection(String)
    /// Memory home (3-pane: Topics sidebar + memorias list + detail).
    case memoryHome
    /// Index home (Catalog / Searches / Monitors / Runs / Alerts tabs).
    case indexHome
    /// Marketplace home (My Offers / My Wants / Prospects / Receipts / Inbox).
    /// Surfaces the marketplace/1.0.0 peer-to-peer protocol state.
    case marketplaceHome
    /// Drive admin (full hierarchical browser).
    case driveAdmin
    /// Drive Photos timeline (curated grid of images).
    case drivePhotos
    /// Drive Documents (curated list of non-image files).
    case driveDocuments
    /// Drive Recent (last viewed items).
    case driveRecent
    /// Drive folder navigation (admin view focused on a specific folder).
    case driveFolder(String)
    /// Calendar mini-app home.
    case calendarHome
    /// Contacts mini-app home.
    case contactsHome
    /// Skills catalog (⌘⇧K). Top-level destination: a full page with
    /// search, filters, grid of cards. Click a card → `.skillDetail`.
    case skills
    /// Detail panel for a single skill — activation toggles, params
    /// form, sync targets, body editor.
    case skillDetail(slug: String)
    /// IoT home — sidebar entry "Home". Renders the Home Assistant–
    /// style screen (Devices / Scenes / Automations / Approvals / Add).
    case iotHome
    /// Detail panel for a single IoT thing. Reached from a card tap.
    case iotThingDetail(id: String)
    /// Design surface: Styles landing (grid of moodboards).
    case designStylesHome
    /// Design surface: Style detail (tokens, brand, voice, imagery,
    /// overrides, references, examples).
    case designStyleDetail(id: String)
    /// Design surface: Templates gallery grouped by category.
    case designTemplatesHome
    /// Design surface: Template detail with rendered preview and slot
    /// inventory.
    case designTemplateDetail(id: String)
    /// Design surface: References inspiration library.
    case designReferencesHome
    /// Design surface: Editor canvas open on a specific EditorDocument
    /// (a Template instance + Style). Reached from TemplateDetailView's
    /// "Open in editor" CTA or from a previously created document.
    case designEditor(documentId: String)
    /// Agents catalog (grid of agents with avatar + name + role).
    case agentsHome
    /// Detail view for a single agent. Tabs: Chats / Skills /
    /// Secrets / Projects / Integrations / Settings.
    case agentDetail(id: String)
    /// Personalities catalog (reusable system-prompt fragments that
    /// can be plugged into an agent).
    case personalitiesHome
    /// Detail view for a single personality.
    case personalityDetail(id: String)
    /// Skill Collections catalog (tagged bundles of skills that an
    /// agent can subscribe to).
    case skillCollectionsHome
    /// Detail view for a single Skill Collection.
    case skillCollectionDetail(id: String)
    /// Connections catalog (Telegram, Slack, ... — auth/token lives
    /// per Connection, individual agents bind to specific channels).
    case connectionsHome
    /// Detail view for a single Connection.
    case connectionDetail(id: String)
    /// Publishing home (Calendar landing inside Tools section). Routes the
    /// month/week calendar of scheduled posts.
    case publishingHome
    /// Publishing composer panel. `prefillBody` is non-nil when the user
    /// pushed an assistant message into the composer; `prefillScheduleAt`
    /// is set when opening the composer from a calendar day.
    case publishingComposer(prefillBody: String?, prefillScheduleAt: Date?)
    /// Publishing channels list. Shows every family with its connect / coming
    /// soon state.
    case publishingChannels
    /// Life home — sidebar entry "Life". Renders the user-data tracking
    /// catalog (the 80-vertical registry) with a 3-pane explorer.
    case lifeHome
    /// Detail panel for a single life vertical (health, sleep, workouts,
    /// emotions, finance, etc.). The id matches the registry entry id.
    case lifeVertical(id: String)
    /// Life settings: show / hide / reorder verticals.
    case lifeSettings
}

extension SidebarRoute {
    var gatedFeature: AppFeature? {
        switch self {
        case .appsHome, .app:
            return .apps
        case .secretsHome:
            return .secrets
        case .databaseHome:
            return .database
        case .databaseWorkbench:
            return .databaseWorkbench
        case .indexHome:
            return .index
        case .marketplaceHome:
            return .marketplace
        case .calendarHome:
            return .calendar
        case .contactsHome:
            return .contacts
        case .skills, .skillDetail:
            return .skills
        case .iotHome, .iotThingDetail:
            return .iotHome
        case .designStylesHome, .designStyleDetail, .designTemplatesHome,
             .designTemplateDetail, .designReferencesHome, .designEditor:
            return .design
        case .agentsHome, .agentDetail, .personalitiesHome, .personalityDetail,
             .connectionsHome, .connectionDetail:
            return .agents
        case .skillCollectionsHome, .skillCollectionDetail:
            return .skillCollections
        case .publishingHome, .publishingComposer, .publishingChannels:
            return .publishing
        case .lifeHome, .lifeVertical, .lifeSettings:
            return .life
        case .home, .search, .plugins, .automations, .project, .chat, .settings,
             .databaseCollection, .memoryHome, .driveAdmin, .drivePhotos,
             .driveDocuments, .driveRecent, .driveFolder:
            return nil
        }
    }

    func visibleRoute(isVisible: (AppFeature) -> Bool) -> SidebarRoute {
        guard let feature = gatedFeature, !isVisible(feature) else { return self }
        return .home
    }
}
