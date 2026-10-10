import AppKit
import ScreenSaver

enum SaverScene: String, CaseIterable {
    case shapeFall, warningRain

    var title: String {
        switch self {
        case .shapeFall: return "Shape fall"
        case .warningRain: return "Warning rain"
        }
    }
}

enum RainText: String, CaseIterable {
    case functions, warnings

    var title: String {
        switch self {
        case .functions: return "Functions"
        case .warnings: return "Warnings and errors"
        }
    }
}

enum ShapeColour: String, CaseIterable {
    case ink, palette

    var title: String {
        switch self {
        case .ink: return "Default"
        case .palette: return "Random from hue_pal()"
        }
    }
}

enum FillTime: Int, CaseIterable {
    case s15 = 15, s30 = 30, s60 = 60, s120 = 120

    var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: String { rawValue < 60 ? "\(rawValue) seconds" : rawValue == 60 ? "1 minute" : "\(rawValue / 60) minutes" }
}

struct Options {
    var scene = SaverScene.shapeFall
    var theme = GGTheme.grey
    var shapeColour = ShapeColour.palette
    var fillTime = FillTime.s30
    var rainText = RainText.functions
    var rainColour = ShapeColour.palette

    private static var defaults: ScreenSaverDefaults? {
        let id = Bundle(for: GGSaverView.self).bundleIdentifier ?? "com.gkaramanis.ggsaver"
        return ScreenSaverDefaults(forModuleWithName: id)
    }

    static func load() -> Options {
        var options = Options()
        guard let d = defaults else { return options }
        if let s = d.string(forKey: "scene"), let scene = SaverScene(rawValue: s) { options.scene = scene }
        if let s = d.string(forKey: "theme"), let theme = GGTheme(rawValue: s) { options.theme = theme }

        // "colour" is the single setting both scenes shared before it was split.
        let shared = d.string(forKey: "colour").flatMap(ShapeColour.init)
        options.shapeColour = d.string(forKey: "shapeColour").flatMap(ShapeColour.init) ?? shared ?? options.shapeColour
        options.rainColour = d.string(forKey: "rainColour").flatMap(ShapeColour.init) ?? shared ?? options.rainColour
        if let time = FillTime(rawValue: d.integer(forKey: "fillTime")) { options.fillTime = time }
        if let s = d.string(forKey: "rainText"), let text = RainText(rawValue: s) { options.rainText = text }
        return options
    }

    func save() {
        guard let d = Options.defaults else { return }
        d.set(scene.rawValue, forKey: "scene")
        d.set(theme.rawValue, forKey: "theme")
        d.set(shapeColour.rawValue, forKey: "shapeColour")
        d.set(fillTime.rawValue, forKey: "fillTime")
        d.set(rainText.rawValue, forKey: "rainText")
        d.set(rainColour.rawValue, forKey: "rainColour")
        d.synchronize()
    }
}

/// The Options sheet, built in code so the bundle needs no nib. Scene and
/// Scene is on top; below it only the selected scene's options show.
@MainActor
final class OptionsSheet: NSObject {
    let window: NSWindow
    var onSave: ((Options) -> Void)?

    private let scenePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shapeColourPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let timePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rainTextPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rainColourPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var sections: [SaverScene: [NSView]] = [:]

    private static let width: CGFloat = 380
    private static let height: CGFloat = 270

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        let content = window.contentView!

        scenePopup.addItems(withTitles: SaverScene.allCases.map(\.title))
        themePopup.addItems(withTitles: GGTheme.allCases.map(\.title))
        shapeColourPopup.addItems(withTitles: ShapeColour.allCases.map(\.title))
        timePopup.addItems(withTitles: FillTime.allCases.map(\.title))
        rainTextPopup.addItems(withTitles: RainText.allCases.map(\.title))
        rainColourPopup.addItems(withTitles: ShapeColour.allCases.map(\.title))

        // Rows are laid out top-down; y is the top edge of the next row.
        var y = Self.height - 20

        @discardableResult
        func row(_ title: String, _ popup: NSPopUpButton) -> [NSView] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 20, y: y - 22, width: 125, height: 18)
            label.alignment = .right
            popup.frame = NSRect(x: 150, y: y - 26, width: Self.width - 170, height: 26)
            content.addSubview(label)
            content.addSubview(popup)
            y -= 34
            return [label, popup]
        }

        func header(_ title: String) -> [NSView] {
            y -= 10
            let line = NSBox(frame: NSRect(x: 20, y: y, width: Self.width - 40, height: 1))
            line.boxType = .separator
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            label.frame = NSRect(x: 20, y: y - 28, width: Self.width - 40, height: 18)
            content.addSubview(line)
            content.addSubview(label)
            y -= 34
            return [line, label]
        }

        row("Scene:", scenePopup)
        scenePopup.target = self
        scenePopup.action = #selector(sceneChanged)

        // Both sections take the same rows; only the selected scene's is shown.
        let top = y
        sections[.shapeFall] = header(SaverScene.shapeFall.title)
            + row("Theme:", themePopup)
            + row("Colour:", shapeColourPopup)
            + row("Fill time:", timePopup)
        y = top
        sections[.warningRain] = header(SaverScene.warningRain.title)
            + row("Text:", rainTextPopup)
            + row("Colour:", rainColourPopup)

        let ok = NSButton(title: "OK", target: self, action: #selector(save))
        ok.keyEquivalent = "\r"
        ok.frame = NSRect(x: Self.width - 106, y: 14, width: 90, height: 32)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: Self.width - 200, y: 14, width: 90, height: 32)
        content.addSubview(cancel)
        content.addSubview(ok)
    }

    func show(_ options: Options) {
        scenePopup.selectItem(at: SaverScene.allCases.firstIndex(of: options.scene) ?? 0)
        themePopup.selectItem(at: GGTheme.allCases.firstIndex(of: options.theme) ?? 0)
        shapeColourPopup.selectItem(at: ShapeColour.allCases.firstIndex(of: options.shapeColour) ?? 0)
        timePopup.selectItem(at: FillTime.allCases.firstIndex(of: options.fillTime) ?? 0)
        rainTextPopup.selectItem(at: RainText.allCases.firstIndex(of: options.rainText) ?? 0)
        rainColourPopup.selectItem(at: ShapeColour.allCases.firstIndex(of: options.rainColour) ?? 0)
        sceneChanged()
    }

    @objc private func sceneChanged() {
        let selected = SaverScene.allCases[max(0, scenePopup.indexOfSelectedItem)]
        for (scene, views) in sections {
            for view in views { view.isHidden = scene != selected }
        }
    }

    @objc private func save() {
        var options = Options()
        options.scene = SaverScene.allCases[max(0, scenePopup.indexOfSelectedItem)]
        options.theme = GGTheme.allCases[max(0, themePopup.indexOfSelectedItem)]
        options.shapeColour = ShapeColour.allCases[max(0, shapeColourPopup.indexOfSelectedItem)]
        options.fillTime = FillTime.allCases[max(0, timePopup.indexOfSelectedItem)]
        options.rainText = RainText.allCases[max(0, rainTextPopup.indexOfSelectedItem)]
        options.rainColour = ShapeColour.allCases[max(0, rainColourPopup.indexOfSelectedItem)]
        options.save()
        onSave?(options)
        close()
    }

    @objc private func cancel() { close() }

    // NSApp.endSheet does nothing in the System Settings host, so end the
    // sheet through its parent.
    private func close() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
}
