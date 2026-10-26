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

import Foundation

/// Builds the user-facing URL of a public link.
///
/// The password of a public link is made of a generated part (the first `minSharedLinkRandomPasswordSize`
/// characters) followed by an optional custom part. Only the generated part is embedded in the URL fragment;
/// a custom part has to be shared separately, as the recipient is prompted for it.
public enum PublicLinkFormat {
    public static func link(publicUrl: String, fullPassword: String) -> String {
        let generatedPassword = String(fullPassword.prefix(Constants.minSharedLinkRandomPasswordSize))
        return "\(publicUrl)#\(generatedPassword)"
    }
}

public extension ShareURL {
    /// The URL to hand out to the recipients of this public link. Requires decrypting the link password.
    func fullLink() throws -> String {
        PublicLinkFormat.link(publicUrl: publicUrl, fullPassword: try decryptPassword())
    }
}
