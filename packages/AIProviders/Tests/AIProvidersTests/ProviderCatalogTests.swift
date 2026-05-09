import XCTest
@testable import AIProviders

final class ProviderCatalogTests: XCTestCase {

    func testEveryProviderIDHasACatalogEntry() {
        let cataloged = Set(ProviderCatalog.all.map(\.id))
        let declared = Set(ProviderID.allCases)
        XCTAssertEqual(cataloged, declared,
                       "ProviderCatalog.all is missing or has stale entries vs ProviderID")
    }

    func testCatalogHasNoDuplicateProviders() {
        let ids = ProviderCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count,
                       "Duplicate provider id in ProviderCatalog.all")
    }

    func testNoDuplicateModelIdsWithinAProvider() {
        for definition in ProviderCatalog.all {
            let modelIds = definition.models.map(\.id)
            XCTAssertEqual(
                modelIds.count, Set(modelIds).count,
                "Duplicate model id inside provider \(definition.id.rawValue)"
            )
        }
    }

    func testEveryModelHasAtLeastOneCapability() {
        for definition in ProviderCatalog.all {
            for model in definition.models {
                XCTAssertFalse(
                    model.capabilities.isEmpty,
                    "Model \(model.id) of provider \(definition.id.rawValue) declares no capabilities"
                )
            }
        }
    }

    func testEveryProviderDeclaresAtLeastOneAuthMethod() {
        for definition in ProviderCatalog.all {
            XCTAssertFalse(
                definition.authMethods.isEmpty,
                "Provider \(definition.id.rawValue) has no authMethods"
            )
        }
    }

    func testDefaultModelLookupRespectsIsDefaultFor() {
        // OpenAI advertises gpt-4o as `isDefaultFor: [.chat]`.
        let model = ProviderCatalog.defaultModel(for: .chat, in: .openai)
        XCTAssertEqual(model?.id, "gpt-4o")
    }

    func testFallbackModelLookupWhenNoDefault() {
        // Cursor lists no `isDefaultFor` flags; should still return any
        // model that lists `.chat`.
        let model = ProviderCatalog.defaultModel(for: .chat, in: .cursor)
        XCTAssertNotNil(model)
        XCTAssertTrue(model!.capabilities.contains(.chat))
    }

    func testModelsForCapabilityCoversMultipleProviders() {
        let chatModels = ProviderCatalog.models(for: .chat)
        let providers = Set(chatModels.map(\.providerId))
        XCTAssertGreaterThan(providers.count, 5,
                             ".chat should be available across many providers")
    }

    func testCapabilitiesUnionMatchesModels() {
        let openai = ProviderCatalog.definition(for: .openai)!
        XCTAssertTrue(openai.capabilities.contains(.chat))
        XCTAssertTrue(openai.capabilities.contains(.stt))
        XCTAssertTrue(openai.capabilities.contains(.tts))
        XCTAssertTrue(openai.capabilities.contains(.embeddings))
        XCTAssertTrue(openai.capabilities.contains(.imageGen))
    }
}
