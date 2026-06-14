Threat Model:
1. Backend may be compromised.
2. Network may be observed or attacked.
3. Device may be locked or stolen.
4. App should avoid storing plaintext files permanently.

Trusted:
- iOS device while unlocked.
- Apple Keychain/Secure Enclave.
- App code.

Not Trusted:
- Backend storage.
- Network.
- Raw local file storage outside protected areas.

Out of Scope v0:
- Multi-device key sync.
- Account recovery.
- File sharing.
- Group access.
