import SwiftUI
import FleetRollout
import FleetRolloutUI

/// The compiled-in half of the config system.
///
/// This lives in the **app**, not in the package, and that is the whole point:
/// it is the answer that ships inside the binary, works with the network
/// unplugged, and is what a killed flag resolves to. A config system whose "off"
/// state is defined by the server has no off state at all.
enum CompiledInConfiguration {

    /// The app's own fallback values. `FleetRollout` never invents these.
    static let fallback = FallbackCatalog(values: [
        "checkout.duo_layout": .bool(false),
        "search.rerank": .string("baseline"),
        "media.prefetch_budget_mb": .int(24)
    ])

    static let primaryFlagKey = "checkout.duo_layout"
    static let treatedVariantKeys: Set<String> = ["on"]

    /// The document that ships in the bundle, used before any network fetch and
    /// whenever every remote source has failed.
    ///
    /// It encodes the real shape of the September 2026 release graph:
    ///
    /// - `duo-canary` targets iOS 27.1 **by identity**, not by comparison, so
    ///   it cannot leak onto 27.2. There is no `>=` operator in the language to
    ///   leak with.
    /// - `mainline-ramp` targets 27.2 separately, because the two trains are
    ///   genuinely different audiences with genuinely different code beneath
    ///   them. Under `osVersion >= 27.1` they would have been one audience, and
    ///   the Duo canary would have shipped to 72% of the fleet on day one.
    /// - Both rules gate on `appBuildAtLeast(1_190)`. Ordering is legitimate
    ///   there: the app's own build number is monotonic because we control it.
    /// - `stranded-27.0` exists because iOS 27 closed the downgrade window on
    ///   21 September 2026. Devices that stalled on 27.0 cannot go back, so they
    ///   get a deliberately conservative configuration rather than being swept
    ///   into the mainline rollout.
    /// - Every flag carries its own salt as a *rotation handle*, not as the
    ///   thing that keeps the flags apart. `StableBucketer` hashes the flag key
    ///   too, so these three rollouts are decorrelated by construction and would
    ///   stay decorrelated even if all three salts were identical. What a
    ///   distinct salt buys is the ability to reshuffle one flag's population,
    ///   later, without renaming the flag.
    static let bundledDocument: ConfigDocument = {
        let duoLayout = FlagDefinition(
            key: primaryFlagKey,
            salt: "checkout-duo-2026-09",
            variants: [
                Variant(key: "off", value: .bool(false)),
                Variant(key: "on", value: .bool(true))
            ],
            defaultVariantKey: "off",
            rules: [
                RolloutRule(
                    id: "duo-canary",
                    predicate: .all([
                        .onTrain([BuildTrain.ios27_1Duo.identifier]),
                        .posture(.foldable),
                        .appBuildAtLeast(1_190)
                    ]),
                    variantKey: "on",
                    bucketRange: .percent(10)),
                RolloutRule(
                    id: "mainline-ramp",
                    predicate: .all([
                        .onTrain([BuildTrain.ios27_2.identifier]),
                        .appBuildAtLeast(1_190)
                    ]),
                    variantKey: "on",
                    bucketRange: .percent(10))
            ])

        let rerank = FlagDefinition(
            key: "search.rerank",
            salt: "search-rerank-2026-09",
            variants: [
                Variant(key: "baseline", value: .string("baseline")),
                Variant(key: "on_device", value: .string("on_device"))
            ],
            defaultVariantKey: "baseline",
            rules: [
                RolloutRule(
                    id: "modern-trains",
                    predicate: .onTrain([
                        BuildTrain.ios27_1Duo.identifier,
                        BuildTrain.ios27_2.identifier
                    ]),
                    variantKey: "on_device",
                    bucketRange: .percent(25))
            ])

        let prefetch = FlagDefinition(
            key: "media.prefetch_budget_mb",
            salt: "media-prefetch-2026-09",
            variants: [
                Variant(key: "conservative", value: .int(24)),
                Variant(key: "standard", value: .int(64))
            ],
            defaultVariantKey: "standard",
            rules: [
                RolloutRule(
                    id: "stranded-27.0",
                    predicate: .onLineage([.terminal, .mainline]),
                    variantKey: "conservative",
                    bucketRange: .full)
            ])

        return ConfigDocument(
            documentVersion: 1,
            issuedAt: Date(timeIntervalSince1970: 1_758_585_600),  // 23 Sep 2026
            maxAge: 300,
            staleWhileRevalidate: 86_400,
            flags: [duoLayout, rerank, prefetch],
            integrity: .unsigned)  // the bundled copy needs no signature: it shipped with the binary
    }()
}

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            FleetRolloutDashboard(
                document: CompiledInConfiguration.bundledDocument,
                fallback: CompiledInConfiguration.fallback,
                primaryFlagKey: CompiledInConfiguration.primaryFlagKey,
                treatedVariantKeys: CompiledInConfiguration.treatedVariantKeys,
                fleetSize: 2_000)
        }
    }
}
