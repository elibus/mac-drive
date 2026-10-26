// Copyright (c) 2026 Proton AG
//
// This file is part of Proton Drive.
//
// Proton Drive is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Drive is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Drive. If not, see https://www.gnu.org/licenses/.

import AppKit
import FileProvider
import PDCore
import PDFileProviderOperations

// MARK: - Copy public link action

extension FileProviderExtension {
    static let copyPublicLinkActionIdentifier = "ch.protonmail.drive.fileprovider.action.copy_public_link"

    /// Asks clipboard managers not to record the item: a public link carries its secret in the URL fragment.
    /// See http://nspasteboard.org
    private static let concealedPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private enum PublicLinkError: LocalizedError {
        case unsupportedItem
        case notOwner
        case missingLink
        case partial(copied: Int, failed: Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedItem:
                return "This item cannot be shared with a link."
            case .notOwner:
                return "Only the owner of an item can create a link for it."
            case .missingLink:
                return "The link could not be found after it was created."
            case let .partial(copied, failed):
                return "\(copied) link(s) were copied to the clipboard, but \(failed) item(s) could not be shared."
            }
        }
    }

    /// Creates (or reuses) a read-only public link for each item and puts the link(s) on the clipboard.
    ///
    /// Items are processed independently: links obtained for some items are copied even if others fail,
    /// in which case the action completes with ``PublicLinkError/partial(copied:failed:)``.
    func copyPublicLink(itemsWithIdentifiers itemIdentifiers: [NSFileProviderItemIdentifier],
                        completionBlockWrapper: CompletionBlockWrapper<Error?, Void, Void, Void>) -> Progress {
        Log.info("performAction copy_public_link for \(itemIdentifiers.count) item(s)", domain: .sharing)

        let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))
        progresses.add(progress)

        let task = Task { [weak self] in
            guard let self else {
                completionBlockWrapper(CocoaError(.userCancelled))
                return
            }
            defer { progresses.remove(progress) }

            var links: [String] = []
            var failures: [Error] = []
            for itemIdentifier in itemIdentifiers {
                do {
                    try Task.checkCancellation()
                    links.append(try await makePublicLink(for: itemIdentifier))
                } catch is CancellationError {
                    completionBlockWrapper(CocoaError(.userCancelled))
                    return
                } catch {
                    Log.error("Copy public link failed for an item", error: error, domain: .sharing)
                    failures.append(error)
                }
                progress.completedUnitCount += 1
            }

            guard !links.isEmpty else {
                completionBlockWrapper(failures.first)
                return
            }

            await MainActor.run { Self.copyToClipboard(links) }
            Log.info("Copied \(links.count) public link(s) to the clipboard", domain: .sharing)

            completionBlockWrapper(failures.isEmpty ? nil : PublicLinkError.partial(copied: links.count, failed: failures.count))
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    private func makePublicLink(for itemIdentifier: NSFileProviderItemIdentifier) async throws -> String {
        guard let nodeIdentifier = NodeIdentifier(itemIdentifier) else {
            throw PublicLinkError.unsupportedItem
        }

        let storage = tower.storage
        guard let fileSystemSlot = tower.fileSystemSlot else {
            throw PublicLinkError.unsupportedItem
        }
        let moc = storage.backgroundContext

        // Same rule as `NodeSharingPolicy.isOwner`: only the owner manages the public link of an item.
        let isOwner = await moc.perform {
            guard let node = fileSystemSlot.getNode(nodeIdentifier, moc: moc), node.state == .active else {
                return false
            }
            return node.getNodeRole() == .owner
        }
        guard isOwner else { throw PublicLinkError.notOwner }

        let sharingManager = SharingManager.make(client: tower.client, storage: storage, sessionVault: tower.sessionVault)
        let linkIdentifier = try await sharingManager.getPublicLink(for: nodeIdentifier, permissions: .read)

        return try await moc.perform {
            guard let shareURL = ShareURL.fetch(id: linkIdentifier.id, in: moc) else {
                throw PublicLinkError.missingLink
            }
            return try shareURL.fullLink()
        }
    }

    @MainActor
    private static func copyToClipboard(_ links: [String]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, concealedPasteboardType], owner: nil)
        pasteboard.setString(links.joined(separator: "\n"), forType: .string)
        pasteboard.setString("", forType: concealedPasteboardType)
    }
}
