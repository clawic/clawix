import XCTest
@testable import Clawix

final class RateLimitDecodingTests: XCTestCase {
    func testDecodesSnakeCaseCodexRateLimits() throws {
        let data = Data("""
        {
          "rate_limits": {
            "limit_id": "codex",
            "limit_name": null,
            "primary": {
              "used_percent": 54.0,
              "window_minutes": 300,
              "resets_at": 1778620137
            },
            "secondary": {
              "used_percent": 45.0,
              "window_minutes": 10080,
              "resets_at": 1779143993
            },
            "credits": {
              "has_credits": false,
              "unlimited": false,
              "balance": null
            }
          },
          "rate_limits_by_limit_id": {
            "codex": {
              "limit_id": "codex",
              "primary": {
                "used_percent": 54.0,
                "window_minutes": 300,
                "resets_at": 1778620137
              },
              "secondary": null,
              "credits": null
            }
          }
        }
        """.utf8)

        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: data)

        XCTAssertEqual(response.rateLimits.limitId, "codex")
        XCTAssertEqual(response.rateLimits.primary?.usedPercent, 54)
        XCTAssertEqual(response.rateLimits.primary?.windowDurationMins, 300)
        XCTAssertEqual(response.rateLimits.secondary?.usedPercent, 45)
        XCTAssertEqual(response.rateLimits.credits?.hasCredits, false)
        XCTAssertEqual(response.rateLimitsByLimitId?["codex"]?.primary?.usedPercent, 54)
    }

    func testDecodesCamelCaseBridgeRateLimits() throws {
        let data = Data("""
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": "Codex",
            "primary": {
              "usedPercent": 14,
              "windowDurationMins": 300,
              "resetsAt": 1778222391
            },
            "secondary": null,
            "credits": {
              "hasCredits": true,
              "unlimited": false,
              "balance": "12.34"
            }
          },
          "rateLimitsByLimitId": {}
        }
        """.utf8)

        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: data)

        XCTAssertEqual(response.rateLimits.limitId, "codex")
        XCTAssertEqual(response.rateLimits.limitName, "Codex")
        XCTAssertEqual(response.rateLimits.primary?.usedPercent, 14)
        XCTAssertEqual(response.rateLimits.primary?.resetsAt, 1_778_222_391)
        XCTAssertEqual(response.rateLimits.credits?.balance, "12.34")
        XCTAssertEqual(response.rateLimitsByLimitId?.isEmpty, true)
    }
}
