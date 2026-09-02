import AppKit

/// Monochrome sloppy-joe glyph, loaded as a template image so the system tints
/// it for light/dark menu bars and the highlighted state.
@MainActor
enum MenuBarIcon {
    static let image: NSImage? = {
        let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg")
            ?? Bundle.module.url(forResource: "MenuBarIcon", withExtension: "svg")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}
