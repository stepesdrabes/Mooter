import AppKit
import SwiftUI

/// The status item and its popover. Hand-rolled rather than `MenuBarExtra`: its
/// `.window` style keeps the content alive, and re-rendering, while closed.
final class MenuBar: NSObject, NSPopoverDelegate {
    private let mixer: Mixer
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var clickMonitor: Any?
    /// The click that closed the popover must not reopen it on its way back up.
    private var closingClick: Int?

    init(mixer: Mixer) {
        self.mixer = mixer
        super.init()
        item.autosaveName = "Mooter"
        item.button?.image = .cow
        item.button?.setAccessibilityLabel("Mooter")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.delegate = self
    }

    @objc private func toggle() {
        if let closingClick, closingClick == Self.currentClick {
            self.closingClick = nil
            return
        }
        guard !popover.isShown, let button = item.button else {
            popover.performClose(nil)
            return
        }
        let host = NSHostingController(rootView: MixerView(mixer: mixer))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        // A transient popover closes the instant it opens unless the app is active.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // .transient misses clicks in other apps, so watch for those ourselves.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        clickMonitor.map(NSEvent.removeMonitor)
        clickMonitor = nil
        closingClick = Self.currentClick
        // Drop the view, so nothing renders or polls while the popover is closed.
        popover.contentViewController = nil
    }

    /// `eventNumber` throws on anything but a mouse event, and Esc closes the popover too.
    private static var currentClick: Int? {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseUp else { return nil }
        return event.eventNumber
    }
}

private extension NSImage {
    /// A cow's face: ears, horns, eyes and a big muzzle. A template, so it
    /// follows the menu bar's appearance.
    static let cow: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h))
            }
            func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
            }
            func paint(_ operation: NSCompositingOperation, _ paths: NSBezierPath...) {
                NSGraphicsContext.current?.compositingOperation = operation
                paths.forEach { $0.fill() }
            }
            NSColor.black.setFill()
            paint(.sourceOver, oval(0.5, 5, 5.5, 3.6), oval(14, 5, 5.5, 3.6),       // ears
                  rounded(5.4, 0.6, 2.2, 4, 1.1), rounded(12.4, 0.6, 2.2, 4, 1.1),  // horns
                  rounded(4.5, 2.4, 11, 10.5, 4.6))                                 // head
            paint(.destinationOut, oval(2.6, 8.6, 14.8, 9.4),                       // gap above the muzzle
                  oval(6.9, 5.9, 2, 2.4), oval(11.1, 5.9, 2, 2.4))                  // eyes
            paint(.sourceOver, oval(3.5, 9.5, 13, 7.6))                             // muzzle
            paint(.destinationOut, oval(7, 11.8, 1.9, 2.6), oval(11.1, 11.8, 1.9, 2.6)) // nostrils
            return true
        }
        image.isTemplate = true
        return image
    }()
}
