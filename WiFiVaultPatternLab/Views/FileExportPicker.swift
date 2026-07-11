import SwiftUI
import UIKit

struct ExportDocumentItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct FileExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    let onFinished: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinished: onFinished) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinished: (Bool) -> Void
        init(onFinished: @escaping (Bool) -> Void) { self.onFinished = onFinished }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinished(!urls.isEmpty) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinished(false) }
    }
}
