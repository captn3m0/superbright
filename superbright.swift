import AppKit
import Foundation
import IOKit
import MetalKit

// MARK: - Incompatible app detection

struct IncompatibleRunningApp: Equatable {
    let displayName: String
    let bundleIdentifier: String?
}

private struct IncompatibleAppSignature {
    let displayName: String
    let bundleIdentifiers: Set<String>
    let normalizedNames: Set<String>
}

private let incompatibleAppSignatures: [IncompatibleAppSignature] = [
    IncompatibleAppSignature(
        displayName: "f.lux",
        bundleIdentifiers: ["org.herf.Flux"],
        normalizedNames: ["flux", "fluxapp"]
    ),
    IncompatibleAppSignature(
        displayName: "MonitorControl",
        bundleIdentifiers: ["me.guillaumeb.MonitorControl", "app.monitorcontrol.MonitorControl", "app.monitorcontrol.MonitorControlLite"],
        normalizedNames: ["monitorcontrol"]
    ),
    IncompatibleAppSignature(
        displayName: "BetterDisplay",
        bundleIdentifiers: ["com.github.wulkano.BetterDisplay", "pro.betterdisplay.BetterDisplay"],
        normalizedNames: ["betterdisplay", "betterdummy"]
    ),
    IncompatibleAppSignature(
        displayName: "Lunar",
        bundleIdentifiers: ["fyi.lunar.Lunar"],
        normalizedNames: ["lunar"]
    ),
    IncompatibleAppSignature(
        displayName: "Vivid",
        bundleIdentifiers: ["com.getvivid.vivid", "com.getvivid.Vivid"],
        normalizedNames: ["vivid"]
    ),
    IncompatibleAppSignature(
        displayName: "DisplayBuddy",
        bundleIdentifiers: ["com.sids.DisplayBuddy", "com.sids.displaybuddy-setapp"],
        normalizedNames: ["displaybuddy"]
    ),
    IncompatibleAppSignature(
        displayName: "Gamma Control",
        bundleIdentifiers: ["ca.michelf.gamma-control"],
        normalizedNames: ["gammacontrol"]
    ),
    IncompatibleAppSignature(
        displayName: "QuickShade",
        bundleIdentifiers: ["jp.questbeat.Shade"],
        normalizedNames: ["quickshade"]
    ),
    IncompatibleAppSignature(
        displayName: "Iris",
        bundleIdentifiers: ["com.iristech.Iris", "com.iristech.IrisMini"],
        normalizedNames: ["iris", "irismini"]
    ),
]

private func normalizedApplicationName(_ name: String) -> String {
    name.lowercased().filter { $0.isLetter || $0.isNumber }
}

private func normalizedApplicationCandidates(for app: NSRunningApplication) -> Set<String> {
    Set([app.localizedName, app.bundleIdentifier,
         app.bundleURL?.deletingPathExtension().lastPathComponent,
         app.executableURL?.deletingPathExtension().lastPathComponent]
        .compactMap { $0.map(normalizedApplicationName) })
}

@MainActor func runningIncompatibleApps() -> [IncompatibleRunningApp] {
    let currentBundleIdentifier = Bundle.main.bundleIdentifier
    var foundApps: [IncompatibleRunningApp] = []

    for app in NSWorkspace.shared.runningApplications {
        guard app.bundleIdentifier != currentBundleIdentifier else { continue }

        let bundleIdentifier = app.bundleIdentifier
        let normalizedBundleIdentifier = bundleIdentifier?.lowercased()
        let normalizedCandidates = normalizedApplicationCandidates(for: app)

        guard let signature = incompatibleAppSignatures.first(where: { sig in
            sig.bundleIdentifiers.contains(where: { $0 == normalizedBundleIdentifier }) ||
            normalizedCandidates.contains(where: { c in sig.normalizedNames.contains(where: { c.contains($0) }) })
        }) else { continue }

        if !foundApps.contains(where: { $0.displayName == signature.displayName }) {
            foundApps.append(IncompatibleRunningApp(
                displayName: signature.displayName,
                bundleIdentifier: bundleIdentifier
            ))
        }
    }

    return foundApps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
}

// MARK: - Device gating

let supportedDevices: Set<String> = [
    "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
    "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10",
    "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
    "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8",
    "Mac17,2", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9",
]

let externalXdrDisplays: Set<String> = ["Pro Display XDR", "Studio Display XDR"]

let sdr600nitsDevices: Set<String> = [
    "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
    "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8",
    "Mac17,2", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9",
]

// MARK: - Display helpers

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

func getModelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    defer { IOObjectRelease(service) }
    guard let data = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)
        .takeRetainedValue() as? Data else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
}

func isDeviceSupported() -> Bool {
    getModelIdentifier().map { supportedDevices.contains($0) } ?? false
}

func isClamshellClosed() -> Bool? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    let clamshellState = IORegistryEntryCreateCFProperty(
        service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
    )?.takeRetainedValue()
    if let value = clamshellState as? Bool { return value }
    if let number = clamshellState as? NSNumber { return number.boolValue }
    return nil
}

func isBuiltInScreen(_ screen: NSScreen) -> Bool {
    guard let displayId = screen.displayId else { return false }
    return CGDisplayIsBuiltin(displayId) != 0
}

func isExternalXDRDisplay(_ screen: NSScreen) -> Bool {
    externalXdrDisplays.contains(screen.localizedName)
}

func isScreenSupported(_ screen: NSScreen) -> Bool {
    if isBuiltInScreen(screen) && isDeviceSupported() { return true }
    if isExternalXDRDisplay(screen) { return true }
    return false
}

@MainActor func getXDRDisplays() -> [NSScreen] {
    NSScreen.screens.filter { isScreenSupported($0) }
}

func hasExternalXDR() -> Bool {
    NSScreen.screens.contains { isExternalXDRDisplay($0) }
}

func getScreenRefGamma(_ screen: NSScreen) -> (refEdr: Float, bonusGamma: Float) {
    if let displayId = screen.displayId, CGDisplayIsBuiltin(displayId) != 0 {
        if let device = getModelIdentifier(), sdr600nitsDevices.contains(device) {
            return (2.66, 0.50)
        }
        return (3.2, 0.59)
    }
    return (2.66, 0.6)
}

func brightnessFactor(screen: NSScreen, maxEdr: CGFloat) -> Float {
    let (refEdr, bonusGamma) = getScreenRefGamma(screen)
    return 1 + bonusGamma * min(Float(maxEdr) / refEdr, 1.0)
}

// MARK: - Gamma table

final class GammaTable {
    static let tableSize: UInt32 = 256
    private static let boostedBaselineThreshold: CGGammaValue = 1.1

    var redTable: [CGGammaValue] = .init(repeating: 0, count: Int(tableSize))
    var greenTable: [CGGammaValue] = .init(repeating: 0, count: Int(tableSize))
    var blueTable: [CGGammaValue] = .init(repeating: 0, count: Int(tableSize))

    private init() {}

    static func capture(displayId: CGDirectDisplayID) -> GammaTable? {
        let table = GammaTable()
        var sampleCount: UInt32 = 0
        let result = CGGetDisplayTransferByTable(
            displayId, tableSize,
            &table.redTable, &table.greenTable, &table.blueTable,
            &sampleCount)
        return result == .success ? table : nil
    }

    static func cleanBaseline(displayId: CGDirectDisplayID) -> GammaTable? {
        guard let current = capture(displayId: displayId) else { return nil }
        guard current.appearsBoosted else { return current }

        CGDisplayRestoreColorSyncSettings()

        guard let restored = capture(displayId: displayId) else {
            return current.normalizedByMaximum()
        }
        guard restored.appearsBoosted else { return restored }
        return restored.normalizedByMaximum()
    }

    func apply(displayId: CGDirectDisplayID, factor: Float = 1.0) {
        var r = redTable
        var g = greenTable
        var b = blueTable
        for i in 0..<r.count {
            r[i] *= factor
            g[i] *= factor
            b[i] *= factor
        }
        CGSetDisplayTransferByTable(displayId, GammaTable.tableSize, &r, &g, &b)
    }

    private var maximumValue: CGGammaValue {
        max(redTable.max() ?? 0, greenTable.max() ?? 0, blueTable.max() ?? 0)
    }

    private var appearsBoosted: Bool {
        maximumValue > Self.boostedBaselineThreshold
    }

    private func normalizedByMaximum() -> GammaTable? {
        let m = maximumValue
        guard m > 0 else { return nil }
        let table = GammaTable()
        table.redTable = redTable.map { $0 / m }
        table.greenTable = greenTable.map { $0 / m }
        table.blueTable = blueTable.map { $0 / m }
        return table
    }
}

// MARK: - EDR overlay

final class Overlay: MTKView, MTKViewDelegate {
    private let extendedColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    private var commandQueue: MTLCommandQueue?

    init(frame: CGRect) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        guard let device else { fatalError("No metal device") }

        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        commandQueue = device.makeCommandQueue()
        delegate = self
        colorPixelFormat = .rgba16Float
        colorspace = extendedColorSpace
        clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
        preferredFramesPerSecond = 5

        if let layer = layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.pixelFormat = .rgba16Float
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func draw(in view: MTKView) {
        guard let commandQueue,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor),
            let drawable = view.currentDrawable
        else {
            return
        }
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

final class OverlayWindow: NSWindow {
    var overlay: Overlay?

    init() {
        let rect = NSRect(x: 0, y: 0, width: 1, height: 1)
        super.init(
            contentRect: rect,
            styleMask: [],
            backing: BackingStoreType(rawValue: 0)!,
            defer: false)
        collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        level = .screenSaver
        animationBehavior = .none
        canHide = false
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        alphaValue = 1
    }

    func install(on screen: NSScreen) {
        let overlay = Overlay(frame: NSRect(origin: .zero, size: frame.size))
        overlay.autoresizingMask = [.width, .height]
        contentView = overlay
        self.overlay = overlay
        position(on: screen)
        orderFrontRegardless()
        overlay.draw()
    }

    func position(on screen: NSScreen) {
        var origin = screen.frame.origin
        origin.y += screen.frame.height - 1
        setFrameOrigin(origin)
    }
}

// MARK: - Brightness service

@MainActor
final class BrightnessService {
    private var overlayWindows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var baselineGammaTables: [CGDirectDisplayID: GammaTable] = [:]
    private var hdrPollTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var hdrReadyDisplayIds: Set<CGDirectDisplayID> = []
    private var appliedFactors: [CGDirectDisplayID: Float] = [:]
    private var screenUpdateDebounceTask: Task<Void, Never>?

    private let pollInterval: Duration = .milliseconds(500)
    private let hdrReadyThreshold: CGFloat = 1.05
    private let maxEdrEpsilon: CGFloat = 0.0001
    private let factorEpsilon: Float = 0.001

    func start() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenParameters),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleScreensSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification, object: nil)

        CGDisplayRestoreColorSyncSettings()
        apply(screens: shouldDisableForClosedLid() ? [] : getXDRDisplays())
    }

    func stop() {
        screenUpdateDebounceTask?.cancel()
        hdrPollTasks.values.forEach { $0.cancel() }
        hdrPollTasks.removeAll()
        hdrReadyDisplayIds.removeAll()

        for (displayId, table) in baselineGammaTables {
            table.apply(displayId: displayId, factor: 1.0)
        }
        baselineGammaTables.removeAll()
        appliedFactors.removeAll()

        for window in overlayWindows.values { window.close() }
        overlayWindows.removeAll()

        CGDisplayRestoreColorSyncSettings()
    }

    private func apply(screens: [NSScreen]) {
        let activeIds = Set(screens.compactMap { $0.displayId })
        let trackedIds = Set(overlayWindows.keys)
            .union(baselineGammaTables.keys)
            .union(hdrPollTasks.keys)

        for id in trackedIds where !activeIds.contains(id) {
            tearDown(displayId: id)
        }

        for screen in screens {
            guard let displayId = screen.displayId else { continue }

            if baselineGammaTables[displayId] == nil {
                CGDisplayRestoreColorSyncSettings()
                if let table = GammaTable.cleanBaseline(displayId: displayId) {
                    baselineGammaTables[displayId] = table
                }
            }

            if overlayWindows[displayId] == nil {
                let window = OverlayWindow()
                window.install(on: screen)
                overlayWindows[displayId] = window
            } else {
                overlayWindows[displayId]?.position(on: screen)
            }

            if hdrPollTasks[displayId] == nil {
                hdrPollTasks[displayId] = Task { @MainActor [weak self] in
                    await self?.pollHDR(displayId: displayId)
                }
            }
        }

        adjustReadyDisplays()
    }

    private func tearDown(displayId: CGDirectDisplayID) {
        hdrPollTasks[displayId]?.cancel()
        hdrPollTasks.removeValue(forKey: displayId)
        hdrReadyDisplayIds.remove(displayId)
        appliedFactors.removeValue(forKey: displayId)
        if let table = baselineGammaTables.removeValue(forKey: displayId) {
            table.apply(displayId: displayId, factor: 1.0)
        }
        overlayWindows.removeValue(forKey: displayId)?.close()
    }

    private func pollHDR(displayId: CGDirectDisplayID) async {
        var lastMaxEdr: CGFloat?
        while !Task.isCancelled {
            guard let screen = NSScreen.screens.first(where: { $0.displayId == displayId }) else {
                hdrReadyDisplayIds.remove(displayId)
                return
            }
            let maxEdr = screen.maximumExtendedDynamicRangeColorComponentValue
            let ready = maxEdr > hdrReadyThreshold
            let wasReady = hdrReadyDisplayIds.contains(displayId)

            if ready {
                hdrReadyDisplayIds.insert(displayId)
                if !wasReady || lastMaxEdr.map({ abs($0 - maxEdr) > maxEdrEpsilon }) ?? true {
                    lastMaxEdr = maxEdr
                    applyGamma(displayId: displayId, screen: screen, maxEdr: maxEdr)
                }
            } else if wasReady {
                hdrReadyDisplayIds.remove(displayId)
                lastMaxEdr = nil
                restoreGamma(displayId: displayId)
            }

            try? await Task.sleep(for: pollInterval)
        }
    }

    private func adjustReadyDisplays() {
        for displayId in hdrReadyDisplayIds {
            guard let screen = NSScreen.screens.first(where: { $0.displayId == displayId }) else {
                continue
            }
            applyGamma(
                displayId: displayId,
                screen: screen,
                maxEdr: screen.maximumExtendedDynamicRangeColorComponentValue)
        }
    }

    private func applyGamma(displayId: CGDirectDisplayID, screen: NSScreen, maxEdr: CGFloat) {
        guard let table = baselineGammaTables[displayId] else { return }
        let factor = brightnessFactor(screen: screen, maxEdr: maxEdr)
        if let last = appliedFactors[displayId], abs(last - factor) <= factorEpsilon { return }
        table.apply(displayId: displayId, factor: factor)
        appliedFactors[displayId] = factor
    }

    private func restoreGamma(displayId: CGDirectDisplayID) {
        guard let table = baselineGammaTables[displayId] else { return }
        table.apply(displayId: displayId, factor: 1.0)
        appliedFactors[displayId] = 1.0
    }

    @objc private func handleScreenParameters() {
        scheduleDebouncedScreenUpdate()
    }

    @objc private func handleWakeFromSleep() {
        Task { @MainActor in
            CGDisplayRestoreColorSyncSettings()
            self.scheduleDebouncedScreenUpdate()
        }
    }

    @objc private func handleScreensSleep() {
        Task { @MainActor in
            CGDisplayRestoreColorSyncSettings()
        }
    }

    private func shouldDisableForClosedLid() -> Bool {
        isClamshellClosed() ?? false
    }

    private func scheduleDebouncedScreenUpdate() {
        screenUpdateDebounceTask?.cancel()
        screenUpdateDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.apply(screens: shouldDisableForClosedLid() ? [] : getXDRDisplays())
        }
    }
}

// MARK: - Daemonize

func daemonize() -> Never {
    guard let executableURL = Bundle.main.executableURL else {
        FileHandle.standardError.write(Data("superbright: failed to resolve executable path\n".utf8))
        exit(1)
    }
    let forwarded = CommandLine.arguments
        .dropFirst()
        .filter { $0 != "-d" && $0 != "--daemon" }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = Array(forwarded)
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        FileHandle.standardError.write(Data("superbright: failed to daemonize: \(error)\n".utf8))
        exit(1)
    }

    let pid = process.processIdentifier
    print(
        """
        superbright running in the background (pid \(pid)).

        To stop it:
            kill \(pid)
            # or
            pkill -x superbright
        """)
    exit(0)
}

// MARK: - Signal handling

func installSignalHandlers(onSignal: @escaping () -> Void) -> [DispatchSourceSignal] {
    let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]
    var sources: [DispatchSourceSignal] = []
    for sig in signals {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler(handler: onSignal)
        source.resume()
        sources.append(source)
    }
    return sources
}

// MARK: - Usage

func printUsage() {
    let text = """
        superbright — extra brightness for XDR Macs
        Usage: superbright [options]

        Options:
          -d, --daemon   Detach and run in the background, then exit.
          -h, --help     Show this help message.

        Without options, runs in the foreground. Brightness is restored on exit (Ctrl-C / SIGTERM).
        """
    print(text)
}

// MARK: - Entry point

@main
@MainActor
struct SuperbrightCLI {
    static var sharedSignalSources: [DispatchSourceSignal] = []
    static var sharedService: BrightnessService?

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("-h") || args.contains("--help") {
            printUsage()
            return
        }

        if args.contains("-d") || args.contains("--daemon") {
            daemonize()
        }

        guard isDeviceSupported() || hasExternalXDR() else {
            FileHandle.standardError.write(Data("superbright: this Mac is not supported\n".utf8))
            exit(1)
        }

        let incompatible = runningIncompatibleApps()
        if !incompatible.isEmpty {
            let names = incompatible.map { $0.displayName }.joined(separator: ", ")
            FileHandle.standardError.write(
                Data("superbright: incompatible app(s) detected: \(names)\nQuit them before running superbright.\n".utf8))
            exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let service = BrightnessService()
        sharedService = service
        service.start()

        sharedSignalSources = installSignalHandlers {
            sharedService?.stop()
            exit(0)
        }

        app.run()
    }
}
