import CoreLocation
import Foundation
import MessageUI
import SwiftUI
import UIKit

enum LiveLocationShareFormatter {
    static func shareMessage(
        senderName: String,
        coordinate: CLLocationCoordinate2D,
        context: String
    ) -> String {
        let lat = String(format: "%.6f", coordinate.latitude)
        let lon = String(format: "%.6f", coordinate.longitude)
        let googleMapsURL = "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)"

        return """
        \(senderName) shared a live location through ChhayaAI.
        Context: \(context)
        Coordinates: \(lat), \(lon)
        Open in Google Maps: \(googleMapsURL)
        """
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MessageComposerSheet: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    var onFinish: (() -> Void)? = nil

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposerSheet

        init(parent: MessageComposerSheet) {
            self.parent = parent
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            parent.onFinish?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {
        uiViewController.recipients = recipients
        uiViewController.body = body
    }
}
