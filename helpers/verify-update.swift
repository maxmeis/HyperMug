import CryptoKit
import Foundation

// Verify the archive's Sparkle Ed25519 signature against the public key
// embedded in the app. Inputs are environment/arguments; no key is logged.
guard CommandLine.arguments.count == 3,
      let keyString = ProcessInfo.processInfo.environment["SPARKLE_PUBLIC_ED_KEY"],
      let keyData = Data(base64Encoded: keyString),
      let signature = Data(base64Encoded: CommandLine.arguments[2]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
      let archive = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      key.isValidSignature(signature, for: archive)
else {
    fputs("Sparkle public key signature verification failed\n", stderr)
    exit(1)
}
