import SwiftUI
import UIKit
import Contacts
import ContactsUI

/// Presents the system contact picker (multi-select) while `isPresented` is true.
/// The picker runs out of process, so no Contacts permission prompt is needed and only the
/// people the user picks are shared with the app.
///
/// Use as a zero-size background: `.background(ContactPickerPresenter(isPresented: $show) { picked in … })`.
/// (Putting CNContactPickerViewController directly inside a SwiftUI `.sheet` shows a blank sheet.)
struct ContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([PickedContact]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, !context.coordinator.isShowing else { return }
        context.coordinator.isShowing = true
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        DispatchQueue.main.async {
            if uiViewController.presentedViewController == nil {
                uiViewController.present(picker, animated: true)
            } else {
                context.coordinator.isShowing = false
                isPresented = false
            }
        }
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPickerPresenter
        var isShowing: Bool = false

        init(parent: ContactPickerPresenter) {
            self.parent = parent
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            isShowing = false
            parent.isPresented = false
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            isShowing = false
            let picked: [PickedContact] = contacts.map { Coordinator.reduce($0) }
            parent.isPresented = false
            parent.onPick(picked)
        }

        static func reduce(_ contact: CNContact) -> PickedContact {
            var parts: [String] = []
            if contact.isKeyAvailable(CNContactGivenNameKey), !contact.givenName.isEmpty {
                parts.append(contact.givenName)
            }
            if contact.isKeyAvailable(CNContactFamilyNameKey), !contact.familyName.isEmpty {
                parts.append(contact.familyName)
            }
            var name: String = parts.joined(separator: " ")
            if name.isEmpty, contact.isKeyAvailable(CNContactOrganizationNameKey) {
                name = contact.organizationName
            }
            var numbers: [String] = []
            if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
                numbers = contact.phoneNumbers.map { $0.value.stringValue }
            }
            return PickedContact(id: contact.identifier, name: name.isEmpty ? "Contact" : name, phoneNumbers: numbers)
        }
    }
}
