import Foundation
import FirebaseFunctions

/// Callable Cloud Functions (docs/ARCHITECTURE.md). Times are sent as epoch milliseconds.
@MainActor
final class FirebaseBackendFunctions: BackendFunctions {
    private var functions: Functions { Functions.functions() }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func readable(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == "com.firebase.functions" {
            // Callables throw HttpsError with a human message; surface it.
            return EklendiServiceError.message(ns.localizedDescription)
        }
        return error
    }

    func suggestTime(hangoutId: String, start: Date, end: Date) async throws {
        let payload: [String: Any] = [
            "hangoutId": hangoutId,
            "start": FirebaseBackendFunctions.millis(start),
            "end": FirebaseBackendFunctions.millis(end),
        ]
        do {
            _ = try await functions.httpsCallable("suggestTime").call(payload)
        } catch {
            throw FirebaseBackendFunctions.readable(error)
        }
    }

    func startNewRound(hangoutId: String) async throws {
        let payload: [String: Any] = ["hangoutId": hangoutId]
        do {
            _ = try await functions.httpsCallable("startNewRound").call(payload)
        } catch {
            throw FirebaseBackendFunctions.readable(error)
        }
    }

    func geocode(_ text: String) async throws -> Location {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EklendiServiceError.message("Enter a neighborhood or address.") }
        let payload: [String: Any] = ["text": trimmed]
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("geocodeLocation").call(payload)
        } catch {
            throw FirebaseBackendFunctions.readable(error)
        }
        guard let dict = result.data as? [String: Any],
              let lat = (dict["lat"] as? NSNumber)?.doubleValue,
              let lng = (dict["lng"] as? NSNumber)?.doubleValue else {
            throw EklendiServiceError.message("Couldn't find that place. Try a neighborhood and city, like \"Hyde Park, Chicago\".")
        }
        let label = (dict["text"] as? String) ?? trimmed
        return Location(text: label.isEmpty ? trimmed : label, lat: lat, lng: lng)
    }
}
