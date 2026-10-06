import AppKit

let app = NSApplication.shared
// Info.plist sets LSUIElement for the bundled app; this covers `swift run`.
app.setActivationPolicy(.accessory)
let menuBar = MenuBar(mixer: Mixer())
app.run()
