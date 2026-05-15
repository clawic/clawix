import Foundation

// @persistent-surface-wrapper
public enum ClawixEnv {
    public static let agentRuntime = "CLAWIX_AGENT_RUNTIME"
    public static let bridgeBackendPath = "CLAWIX_BRIDGE_BACKEND_PATH"
    public static let bridgeBearer = "CLAWIX_BRIDGE_BEARER"
    public static let bridgeDefaultsSuite = "CLAWIX_BRIDGE_DEFAULTS_SUITE"
    public static let bridgeDisable = "CLAWIX_BRIDGE_DISABLE"
    public static let bridgeDisableBonjour = "CLAWIX_BRIDGE_DISABLE_BONJOUR"
    public static let bridgeHost = "CLAWIX_BRIDGE_HOST"
    public static let bridgeHTTPPort = "CLAWIX_BRIDGE_HTTP_PORT"
    public static let bridgeInitialTimeoutSeconds = "CLAWIX_BRIDGE_INITIAL_TIMEOUT_SECONDS"
    public static let bridgePort = "CLAWIX_BRIDGE_PORT"
    public static let bridgeRateLimitsTimeoutSeconds = "CLAWIX_BRIDGE_RATE_LIMITS_TIMEOUT_SECONDS"
    public static let bridgeThreadListTimeoutSeconds = "CLAWIX_BRIDGE_THREAD_LIST_TIMEOUT_SECONDS"
    public static let backendHome = "CLAWIX_BACKEND_HOME"
    public static let databaseFile = "CLAWIX_DATABASE_FILE"
    public static let databaseDisable = "CLAWIX_DATABASE_DISABLE"
    public static let deepseekSecretName = "CLAWIX_DEEPSEEK_SECRET_NAME"
    public static let disableBackend = "CLAWIX_DISABLE_BACKEND"
    public static let disableAutofocus = "CLAWIX_DISABLE_AUTOFOCUS"
    public static let disableSignposts = "CLAWIX_DISABLE_SIGNPOSTS"
    public static let dummyMode = "CLAWIX_DUMMY_MODE"
    public static let e2eDictationReport = "CLAWIX_E2E_DICTATION_REPORT"
    public static let e2eEnhancementFail = "CLAWIX_E2E_ENHANCEMENT_FAIL"
    public static let e2eTranscriptionText = "CLAWIX_E2E_TRANSCRIPTION_TEXT"
    public static let experimentalFeatures = "CLAWIX_EXPERIMENTAL_FEATURES"
    public static let fileFixtureDir = "CLAWIX_FILE_FIXTURE_DIR"
    public static let fixtureSeeding = "CLAWIX_FIXTURE_SEEDING"
    public static let forceHangDetector = "CLAWIX_FORCE_HANG_DETECTOR"
    public static let hangMs = "CLAWIX_HANG_MS"
    public static let imageFixtureDir = "CLAWIX_IMAGE_FIXTURE_DIR"
    public static let meshHome = "CLAWIX_MESH_HOME"
    public static let mock = "CLAWIX_MOCK"
    public static let mockOpenFirstChat = "CLAWIX_MOCK_OPEN_FIRST_CHAT"
    public static let openCodeBaseURL = "CLAWIX_OPENCODE_BASE_URL"
    public static let openCodeModel = "CLAWIX_OPENCODE_MODEL"
    public static let openCodePath = "CLAWIX_OPENCODE_PATH"
    public static let openCodePort = "CLAWIX_OPENCODE_PORT"
    public static let permissionMode = "CLAWIX_PERMISSION_MODE"
    public static let persistentSurfaceManifestOut = "CLAWIX_PERSISTENT_SURFACE_MANIFEST_OUT"
    public static let secretsFixture = "CLAWIX_SECRETS_FIXTURE"
    public static let secretsDisable = "CLAWIX_SECRETS_DISABLE"
    public static let secretsProxyPath = "CLAWIX_SECRETS_PROXY_PATH"
    public static let threadFixture = "CLAWIX_THREAD_FIXTURE"

    public static func value(_ key: String, in environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        environment[key]
    }

    public static func isEnabled(_ key: String, in environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[key] == "1"
    }
}

// @persistent-surface-wrapper
public enum ClawEnv {
    public static let home = "CLAW_HOME"
    public static let dataDir = "CLAW_DATA_DIR"
}

// @persistent-surface-wrapper
public enum ClawixMeshRoute {
    public static let prefix = "/v1/mesh/"
    public static let identity = "/v1/mesh/identity"
    public static let peers = "/v1/mesh/peers"
    public static let workspaces = "/v1/mesh/workspaces"
    public static let jobsPrefix = "/v1/mesh/jobs/"
    public static let link = "/v1/mesh/link"
    public static let remoteJobs = "/v1/mesh/remote-jobs"
    public static let pair = "/v1/mesh/pair"
    public static let jobs = "/v1/mesh/jobs"
    public static let jobsCancel = "/v1/mesh/jobs/cancel"
    public static let jobsEvents = "/v1/mesh/jobs/events"
}

// @persistent-surface-wrapper
public enum OllamaAPIRoute {
    public static let version = "/api/version"
    public static let tags = "/api/tags"
    public static let ps = "/api/ps"
    public static let show = "/api/show"
    public static let delete = "/api/delete"
    public static let generate = "/api/generate"
    public static let chat = "/api/chat"
    public static let pull = "/api/pull"
}

// @persistent-surface-wrapper
public enum ClawixDefaultsSurface {
    public static let bridgeSuite = "clawix.bridge"
    public static let binaryPath = "ClawixBinaryPath"
    public static let permissionMode = "ClawixPermissionMode"
    public static let dictationActiveModel = "ClawixBridge.Dictation.ActiveModel"
}

// @persistent-surface-wrapper
public enum ClawixPathSurface {
    public static let bridgeStateDirectory = ".clawix/state"
    public static let bridgeStatusFile = "bridge-status.json"
    public static let bridgeStatusTempFile = "bridge-status.json.tmp"
    public static let cliExecutable = ".clawix/bin/clawix"
    public static let secretsProxySocket = "Library/Application Support/Clawix/secrets/proxy.sock"
    public static let embeddedClawJS = "Clawix/clawjs"
    public static let workspace = "workspace"
    public static let clawWorkspace = ".claw"
    public static let audio = "audio"
}
