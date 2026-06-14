تمام. خلّها Roadmap تنفيذية هدفها الأساسي **تدريب تشفير iOS بعمق**، وليس بناء منتج ضخم. المشروع النهائي يكون قابل للعرض في مقابلة: تطبيق iOS اسمه Secure Vault يشفر الملفات والتسجيلات محليًا، يحفظ المفاتيح بأمان، ثم يرفع ciphertext فقط إلى Backend بسيط.

ابدأ كأنك تبني مشروع من 6 مراحل. كل مرحلة لها نتيجة ملموسة، وتقدر توقف عند أي مرحلة وتكون طلعت بشيء مفيد.

## المرحلة 0: تأسيس المشروع والـ Security Scope

الهدف هنا أنك تحدد وش تبني ووش ما تبني. لا تبدأ بالكود مباشرة قبل ما تكتب صفحة واحدة توضّح التهديدات والتصميم.

المخرجات المطلوبة:

```text
Secure Vault
- iOS app for encrypted voice notes and files.
- Encryption happens on device.
- Server never receives plaintext or encryption keys.
- AES-GCM for file encryption.
- Keychain for key storage.
- Secure Enclave / biometric gate for stronger key access.
- Backend stores ciphertext only.
```

اكتب ملف داخل المشروع:

```text
Docs/SecurityModel.md
```

محتواه يكون بسيط:

```text
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
```

هذه المرحلة مهمة لأنها تخليك تتكلم بلغة أمنية في المقابلة، مو بس “استخدمت CryptoKit”.

---

## المرحلة 1: Local AES-GCM Playground داخل iOS

هنا لا تدخل AVAudioRecorder ولا Backend. فقط خل عندك شاشة بسيطة تجرب فيها تشفير وفك تشفير نص أو Data.

الهدف: تفهم CryptoKit عمليًا.

المخرجات:

```text
CryptoService.swift
```

يحتوي:

```swift
import Foundation
import CryptoKit

struct EncryptedPayload: Codable {
    let algorithm: String
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

final class CryptoService {
    func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    func encrypt(_ data: Data, using key: SymmetricKey) throws -> EncryptedPayload {
        let sealedBox = try AES.GCM.seal(data, using: key)

        return EncryptedPayload(
            algorithm: "AES-256-GCM",
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    func decrypt(_ payload: EncryptedPayload, using key: SymmetricKey) throws -> Data {
        let nonce = try AES.GCM.Nonce(data: payload.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: payload.ciphertext,
            tag: payload.tag
        )

        return try AES.GCM.open(sealedBox, using: key)
    }
}
```

اختبارك العملي:

```text
Input: "hello secure vault"
Encrypt
Decrypt
Output must equal input
```

لا تنتقل للمرحلة الثانية إلا إذا فهمت هذه الكلمات وتقدر تشرحها:

```text
SymmetricKey
AES-GCM
Nonce
Ciphertext
Tag
Authenticated Encryption
Integrity
```

النقطة الذهبية هنا: AES-GCM لا يعطيك سرية فقط، يعطيك أيضًا integrity. يعني لو أحد عدّل ciphertext أو tag، فك التشفير يفشل.

---

## المرحلة 2: تشفير ملف محليًا بدون Keychain

الآن طبّق نفس الفكرة على ملف حقيقي. لا تبدأ بالصوت بعد. استخدم ملف من Bundle أو ملف نصي/صورة من Document Picker.

المخرجات:

```text
VaultFileCryptoService.swift
```

وظيفته:

```text
read file as Data
encrypt Data
save encrypted blob locally
decrypt encrypted blob
write temporary decrypted file
open / preview file
```

التصميم المقترح محليًا:

```text
Application Support/
  Vault/
    encrypted/
      item-id.vault
    metadata/
      item-id.json
```

الـ metadata:

```json
{
  "id": "UUID",
  "displayName": "sample.pdf",
  "originalContentType": "application/pdf",
  "createdAt": "2026-06-10T12:00:00Z",
  "encryption": {
    "algorithm": "AES-256-GCM",
    "nonce": "base64",
    "tag": "base64",
    "keyId": "local-dev-key"
  }
}
```

في هذه المرحلة عادي يكون المفتاح داخل الذاكرة فقط أو hardcoded مؤقتًا لأجل التدريب، لكن اكتب تعليق واضح:

```swift
// Temporary only. Keychain integration comes in Phase 3.
```

النتيجة المطلوبة:

تختار ملف، تضغط Encrypt، ينحفظ الملف المشفّر فقط. تضغط Open، التطبيق يفك التشفير مؤقتًا ويفتح الملف.

هنا تبدأ تحس بالمشروع الحقيقي.

---

## المرحلة 3: Keychain Key Storage

هذه أهم مرحلة للجهة اللي تركز على التشفير. لأن التشفير سهل نسبيًا، لكن إدارة المفاتيح هي الفرق.

بدل ما تولّد مفتاح جديد كل مرة وتضيّعه، سوّي Keychain service.

المخرجات:

```text
KeychainService.swift
KeyManager.swift
```

عندك خيارين:

الخيار الأسهل كبداية: مفتاح رئيسي واحد لكل التطبيق.

```text
Master Key
  -> used to encrypt all files
```

الخيار الأفضل أمنيًا: مفتاح لكل ملف.

```text
File Key per item
  -> encrypts file content

Keychain
  -> stores file key by keyId
```

للتدريب، ابدأ بمفتاح لكل ملف. لأنه يعطيك فهم أفضل.

التدفق:

```text
1. User selects file.
2. Generate random AES-256 file key.
3. Encrypt file with AES-GCM.
4. Store file key in Keychain using keyId.
5. Store ciphertext locally.
6. Store nonce/tag/keyId in metadata.
```

خصائص Keychain المقترحة:

```text
kSecClassGenericPassword
kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

ليه هذا مهم؟

`WhenUnlocked` يعني المفتاح لا يُتاح إلا والجهاز مفتوح.

`ThisDeviceOnly` يعني المفتاح لا ينتقل مع backup إلى جهاز ثاني.

في مقابلة، هذه نقطة ممتازة تقولها:

“Because this is a security-focused vault, I used ThisDeviceOnly semantics to avoid key material migrating to another device through backups.”

انتبه: هذا يعني لو المستخدم حذف التطبيق أو فقد الجهاز، غالبًا يفقد الوصول. وهذا مقبول في v0 لأنك تبني zero-knowledge prototype.

---

## المرحلة 4: Voice Notes Encryption

الآن أدخل الميزة اللي تعطي التطبيق شخصية: تسجيل صوت وتشفيره.

المخرجات:

```text
AudioRecorderService.swift
AudioPlaybackService.swift
VoiceNoteVaultService.swift
```

التدفق:

```text
1. User taps Record.
2. AVAudioRecorder writes to temporary file.
3. After stop, app reads audio bytes.
4. App encrypts bytes using AES-GCM.
5. App deletes plaintext temp file.
6. App stores encrypted .vault file.
7. On playback, app decrypts into temporary protected location.
8. App plays decrypted temp file.
9. App deletes temp decrypted file after playback.
```

هنا عندك نقطة أمنية مهمة جدًا: لا تترك التسجيل الأصلي بعد التشفير.

يعني بعد التشفير:

```swift
try? FileManager.default.removeItem(at: plaintextAudioURL)
```

ولما تفك التشفير للتشغيل، لا تحفظ الملف المفكوك دائمًا. خله temporary وامسحه بعد التشغيل أو عند إغلاق الشاشة.

واجهة التطبيق في هذه المرحلة تكون بسيطة:

```text
VaultView
  - Record Voice Note button
  - Import File button
  - List of vault items

VaultItemDetailView
  - display metadata
  - decrypt and play/open
  - delete
```

لا تضيّع وقتك بتصميم فاخر. واجهة نظيفة تكفي.

---

## المرحلة 5: Biometric Gate + Secure Enclave Concept

هنا نضيف نضج أمني. لا تقول إن Secure Enclave يشفر الملفات مباشرة. الصياغة الصحيحة: Secure Enclave/biometrics يحمي الوصول إلى المفاتيح.

المستوى الأول العملي:

استخدم Keychain Access Control مع biometrics:

```text
SecAccessControlCreateWithFlags(
  nil,
  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
  [.biometryCurrentSet],
  nil
)
```

الفكرة:

```text
Before reading file key from Keychain, user must pass Face ID / Touch ID.
```

هذا ممتاز للتدريب، وأسهل من تصميم key wrapping كامل.

التدفق:

```text
1. User taps encrypted item.
2. App asks Face ID.
3. If success, app reads key from Keychain.
4. App decrypts file.
5. App plays/opens content.
```

المخرجات:

```text
BiometricKeychainService.swift
LocalAuthenticationService.swift
```

النقاط اللي لازم تفهمها:

```text
biometryAny vs biometryCurrentSet
userPresence
devicePasscode
Secure Enclave-backed keys
Keychain access control
```

للـ MVP، استخدم biometric-protected Keychain. لا تدخل في asymmetric wrapping من البداية إلا بعدين.

---

## المرحلة 6: Backend Zero-Knowledge Storage

الآن تدخل الباك إند. لكن خله بسيط جدًا.

الفكرة: السيرفر يستقبل encrypted blob + metadata غير حساسة. لا يعرف المفتاح. لا يعرف plaintext. لا يحاول يفك.

Endpoints كافية:

```http
POST /auth/register
POST /auth/login

POST /vault/items
GET /vault/items
GET /vault/items/{id}
DELETE /vault/items/{id}
```

قاعدة البيانات:

```text
users
- id
- email
- password_hash
- created_at

vault_items
- id
- user_id
- display_name
- item_type
- content_type
- size_bytes
- encryption_algorithm
- nonce_base64
- tag_base64
- key_id
- storage_path
- created_at
```

مهم: لا تخزن encryption key في السيرفر.

Payload الرفع:

```json
{
  "displayName": "voice-note-1.m4a",
  "itemType": "audio",
  "contentType": "audio/mp4",
  "sizeBytes": 482910,
  "encryption": {
    "algorithm": "AES-256-GCM",
    "nonce": "base64",
    "tag": "base64",
    "keyId": "ios-keychain-id",
    "version": 1
  }
}
```

ومعه الملف:

```text
ciphertext blob
```

الـ backend ممكن يكون FastAPI:

```text
app/
  main.py
  auth/
  vault/
    routes.py
    models.py
    service.py
  storage/
    local_storage.py
```

استخدم local disk في البداية، ثم لاحقًا S3-compatible storage لو تبغى.

النتيجة المهمة في المقابلة:

“Even if the backend database and object storage are leaked, the attacker only gets encrypted blobs and non-sensitive metadata.”

ثم كن صادقًا:

“Metadata like file size, timestamps, and content type may still leak some information, so a stronger version would encrypt more metadata or normalize sizes.”

هذه جملة قوية جدًا لأنها تبين أنك فاهم حدود التصميم.

---

## المرحلة 7: Auth Token in Keychain

لا تخزن التوكن في UserDefaults.

المخرجات:

```text
AuthTokenStore.swift
```

خزّن access token في Keychain.

التدفق:

```text
Login
Receive token
Store token in Keychain
Use token in Authorization header
```

هنا تربط أمن التطبيق كاملًا:

```text
File keys -> Keychain
Auth token -> Keychain
Plaintext -> temporary only
Ciphertext -> local/backend storage
```

---

## المرحلة 8: TLS + Certificate Pinning

هذه آخر مرحلة، لكنها ممتازة للعرض. لا تبدأ بها قبل ما upload/download يشتغل.

في iOS، تطبقها داخل `URLSessionDelegate`.

الأفضل تتعلم public key pinning بدل certificate pinning فقط، لأن certificate rotation ممكن يكسر التطبيق.

تحتاج تفهم:

```text
ATS
TLS
ServerTrust
Certificate chain
Public key pinning
Certificate rotation
Backup pins
Dev vs Prod certificates
```

مخرجات المرحلة:

```text
PinnedURLSessionFactory.swift
SecureAPIClient.swift
```

مهم جدًا تضيف `backup pin` في التصميم، حتى لو ما طبقته بالكامل:

```text
Primary public key pin
Backup public key pin
```

في المقابلة تقدر تقول:

“I avoided hard pinning a single leaf certificate only, because certificate rotation would break clients. A better production approach is public key pinning with backup pins and a rotation strategy.”

---

## المرحلة 9: Testing + Security Validation

هنا ترفع جودة المشروع كثير.

اختبارات مهمة:

```text
CryptoServiceTests
- decrypt(encrypt(data)) == data
- tampered ciphertext fails
- tampered tag fails
- wrong key fails
- wrong nonce fails

KeychainTests
- can store key
- can retrieve key
- missing key returns controlled error

VaultFlowTests
- import file
- encrypted file exists
- plaintext temp file removed
- decrypt on demand works
```

اختبار مهم جدًا:

خذ ciphertext وعدّل byte واحد، لازم يفشل decrypt.

هذا يثبت integrity.

---

## المرحلة 10: Interview-Ready Documentation

هذه المرحلة لا تقل أهمية عن الكود. لأنك تبغى تعرض المشروع لجهة حساسة.

اكتب داخل README:

```text
Secure Vault is an iOS security prototype focused on client-side encryption,
key management, and zero-knowledge backend storage.
```

ثم:

```text
Security Features:
- AES-256-GCM authenticated encryption using CryptoKit
- Per-file symmetric keys
- Keychain-protected key storage
- Optional biometric gate before key access
- Plaintext stored only temporarily
- Backend stores ciphertext only
- Auth token stored in Keychain
- TLS with certificate/public-key pinning
```

ثم قسم مهم:

```text
Known Limitations:
- No multi-device key sync
- No account recovery
- Metadata is partially visible to backend
- Decrypted temporary files exist briefly during playback/opening
- Jailbroken device threat is not fully handled
```

هذا القسم يرفع مصداقيتك. لا تخفي الحدود. الجهات الأمنية تحب الشخص اللي يعرف trade-offs.

---

## الترتيب الزمني المقترح

لو تبغى تنفذه بتركيز، امشِ كذا:

الأسبوع الأول: CryptoKit محليًا

```text
Day 1: SecurityModel.md + project setup
Day 2: CryptoService encrypt/decrypt Data
Day 3: Unit tests for AES-GCM
Day 4: File import + encrypt local file
Day 5: Decrypt + preview local file
```

الأسبوع الثاني: Keychain + Voice

```text
Day 6: KeychainService
Day 7: per-file key management
Day 8: AVAudioRecorder
Day 9: encrypt voice note after recording
Day 10: decrypt and play voice note
```

الأسبوع الثالث: Hardening

```text
Day 11: delete plaintext temp files
Day 12: biometric-protected key access
Day 13: better errors and UI states
Day 14: security tests
Day 15: README + architecture diagram
```

الأسبوع الرابع: Backend + Pinning

```text
Day 16: FastAPI auth
Day 17: upload ciphertext
Day 18: list/download/delete encrypted items
Day 19: iOS API integration
Day 20: TLS/pinning experiment
```

---

## أفضل نسخة MVP لا تتعداها بالبداية

لا تبني كل شيء مرة وحدة. النسخة الذهبية الأولى تكون:

```text
iOS-only Secure Vault:
- Record voice note
- Encrypt with AES-GCM
- Store ciphertext locally
- Store key in Keychain
- Require Face ID before decrypt
- Play decrypted audio temporarily
- Delete plaintext temp files
```

هذه كافية جدًا كبداية، ومباشرة تخدم هدفك.

بعدها أضف:

```text
Backend ciphertext upload/download
Certificate pinning
```

---

## أهم الملفات في مشروع iOS

هيكلة بسيطة:

```text
SecureVault/
  App/
    SecureVaultApp.swift

  Features/
    Vault/
      VaultView.swift
      VaultViewModel.swift
      VaultItemDetailView.swift

    Recorder/
      AudioRecorderService.swift
      AudioPlaybackService.swift

    Importer/
      DocumentImportService.swift

  Security/
    CryptoService.swift
    KeychainService.swift
    KeyManager.swift
    LocalAuthenticationService.swift

  Storage/
    VaultLocalStore.swift
    VaultMetadataStore.swift
    TemporaryPlaintextStore.swift

  Networking/
    APIClient.swift
    PinnedURLSessionFactory.swift

  Models/
    VaultItem.swift
    EncryptedPayload.swift
    EncryptionMetadata.swift

  Docs/
    SecurityModel.md
```

لا تسوي MVVM مبالغ. خليها واضحة. المهم الأمن والتدفق.

---

## تعريف النجاح

أنت تعتبر أن المشروع ناجح لما تقدر تعرض هذا السيناريو:

تفتح التطبيق، تسجل صوت، تضغط حفظ، التطبيق يشفر الصوت ويحذف الملف الأصلي، يظهر العنصر في الخزنة. لما تفتحه، يطلب Face ID، بعدها يفك التشفير ويشغل الصوت. بعدين ترفع نفس الـ ciphertext للسيرفر، وتحملها من جهازك، وتفكها محليًا. السيرفر لا يعرف أي شيء عن المحتوى.

هذا السيناريو إذا شرحته صح، يعطي انطباع قوي جدًا:

“هذا شخص iOS فاهم security، مو بس يعرف يبني شاشات.”
