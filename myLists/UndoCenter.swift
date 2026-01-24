import Foundation
import Combine

@MainActor
final class UndoCenter: ObservableObject {
    struct PendingUndo: Equatable {
        enum Kind: Equatable {
            case list(UUID)
            case item(UUID, UUID)
            case bulkItems([UUID], UUID) // itemIDs, listID
        }

        let kind: Kind
        let message: String
        let expiresAt: Date
    }

    @Published var pending: PendingUndo?

    private var finalizeWorkItem: DispatchWorkItem?

    func setPending(_ pending: PendingUndo, finalize: @escaping @MainActor () -> Void) {
        clearPending()
        self.pending = pending

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.pending == pending {
                    self.pending = nil
                    finalize()
                }
            }
        }
        finalizeWorkItem = work

        let delay = max(0, pending.expiresAt.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func clearPending() {
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil
        pending = nil
    }
}
