# Card Forge Archive (CFA) 1.0

Status: initial design standard, pending implementation and interoperability tests.
Extension: .cfa. Product: Card Forge Engine.
This document defines the container, not the gameplay API or card-data schema.
No existing archive reader or exporter implements this specification yet.

MUST, MUST NOT and SHOULD describe requirements for a conforming implementation.
All byte offsets below are zero-based. All binary integers are unsigned,
little-endian. A byte means eight bits. Sizes are byte counts.

## 1. Purpose and protection

CFA is a dedicated encrypted container, not ZIP renamed with another extension.
It protects stored assets against casual inspection and detects modification
without knowledge of its secret key. Its format is public and may be implemented
by independent exporters and readers.

The entry index, filenames, package type, logical UUID, display name, thumbnail
and all embedded content MUST be encrypted. Only the fixed header is plaintext.
File size, key identifier, random container identifier and ciphertext lengths
remain observable. Hiding traffic patterns and file sizes is outside this version.

Automatic opening requires a key available to the engine. A determined user can
recover that key or capture decrypted data. Encryption MUST NOT be advertised as
preventing all extraction, proving publisher identity, preventing cheating or
making decrypted Lua code safe. A key holder can construct valid modified files.
Publisher signatures, license enforcement and authoritative server rules are
separate features and are not part of CFA 1.0.

## 2. Filesystem layout

The installed library remains:

    ~/Card Forge Engine/
        MyGame/
            <game-uuid>.cfa
            Sets/
                <set-uuid>.cfa
            Decks.lua
            UIO.cfa
            GEO.cfa
            AO.cfa

MyGame is a readable folder name. The game archive is named with its game UUID.
Card set archives are named with their CFS set UUIDs. Override filenames retain
the agreed UIO, GEO and AO abbreviations. They use the same encrypted container.

Decks.lua is the explicitly separate, user-editable deck file. It is not protected
by archive encryption and MUST NOT contain secret rules or keys. Game rules and
deck-building validation belong inside the game archive. Optional overrides
contain UI, graphical-effects and animation data respectively.

Discovering files does not mean their containers or content are valid. The
current filesystem discovery service only identifies candidates. A future
reader MUST authenticate each candidate before using its metadata.

## 3. Physical structure

    128-byte fixed header
    authenticated encrypted index (including its 16-byte authentication tag)
    encrypted entry 1 (including its 16-byte authentication tag)
    encrypted entry 2 (including its 16-byte authentication tag)
    ...

The encrypted index immediately follows the header. The payload immediately
follows the encrypted index. Entry offsets are relative to the payload start.
There are no plaintext filenames, central directory, padding or trailing bytes.

### Header

| Offset | Size | Field | Required value or meaning |
| --- | --- | --- | --- |
| 0 | 8 | Magic | Hex 43 46 41 0D 0A 1A 0A 00 |
| 8 | 2 | Major | 1 |
| 10 | 2 | Minor | 0 |
| 12 | 4 | HeaderSize | 128 |
| 16 | 2 | CipherSuite | 1: XChaCha20-Poly1305-IETF |
| 18 | 2 | Flags | 0 |
| 20 | 4 | ReservedA | All zero |
| 24 | 16 | KeyID | Opaque random key lookup identifier |
| 40 | 16 | ContainerID | Fresh random identifier for this physical export |
| 56 | 24 | IndexNonce | Fresh random index encryption nonce |
| 80 | 8 | IndexCipherSize | Encrypted index bytes, including tag |
| 88 | 8 | PayloadSize | Sum of encrypted entry sizes, including tags |
| 96 | 32 | ReservedB | All zero |

KeyID is not a secret and MUST NOT contain key material. ContainerID is not the
game or set UUID. It changes on every export, even when content is unchanged.

The physical file size MUST equal 128 + IndexCipherSize + PayloadSize exactly.
Perform checked arithmetic before allocation or seeking. Readers MUST reject
unknown versions, cipher suites, nonzero flags and nonzero reserved fields.
No fallback to unencrypted data or another archive format is permitted.

## 4. Cryptography and keys

Cipher suite 1 is libsodium's crypto_aead_xchacha20poly1305_ietf combined mode:
32-byte secret key, 24-byte nonce and 16-byte appended authentication tag.
Do not implement a replacement cipher, custom scrambling or a custom MAC.

The exporter MUST generate a fresh cryptographically random 32-byte key for each
physical archive export. Generate KeyID, ContainerID and every nonce with an
operating-system-backed cryptographic random source. Never use math.random,
timestamps, game UUIDs, passwords or deterministic content hashes as keys.

Every encryption operation under one key MUST have a distinct nonce. Exporters
MUST ensure the index nonce and all entry nonces differ. Re-exporting generates
fresh key material and identifiers, even for identical input.

The application supplies a trusted key resolver:

    resolveKey(keyIDBytes) -> 32 secret key bytes, or an explicit failure

The binary KeyID is exactly the 16 bytes in the header. It is an identifier,
never a path, URL or script name. An archive MUST NOT direct the resolver to
load code, fetch a key from a server or access an arbitrary file.

Automatic-unlock deployments MUST ship the corresponding key-provider data with
the exported game, separately from its .cfa ciphertext. There MUST NOT be a
universal CFE secret that decrypts every creator's games. Key-provider packaging
is a runtime/export deployment contract, not a new field in the archive.
That carrier still needs implementation before automatically shipped games can
be loaded. This document does not claim an unimplemented key carrier exists.

The Lua application layer owns archive structure and policy. Cryptographic
operations MUST use a maintained native implementation, such as libsodium,
behind the runtime's Lua binding. LuaEx remains the filesystem provider.
No LuaEx framework modifications are required by this format.

### Index authentication

Encrypt the UTF-8 index bytes with the header's IndexNonce and the resolved key.
The associated data is the exact concatenation:

    ASCII bytes "CFA1IDX", followed by one zero byte
    all 128 original header bytes

This binds the index to the entire header, including both size fields.
The exporter knows index ciphertext size before encryption: plaintext size + 16.

### Entry authentication

Each entry has its own nonce from the authenticated index. Associated data is:

    ASCII bytes "CFA1ENT", followed by one zero byte
    all 128 original header bytes
    uint32 entry ordinal, starting at 1
    uint32 path byte length
    exact ASCII path bytes
    uint64 plaintext Size
    uint64 CipherSize
    uint64 Offset

Concatenate exactly in that order, without separators or terminators beyond the
explicit domain-label zero byte. This binds bytes to their container, index
position, path, sizes and physical position.

A decrypt operation MUST verify the tag before returning or using plaintext.
Index success authenticates the index; it does not authenticate unread entries.
An entry is verified only after its own authentication succeeds. Do not mark
an entire archive verified unless all entries have been verified.

## 5. Encrypted index

The decrypted index is one UTF-8 JSON object. No BOM, duplicate object keys,
invalid UTF-8, non-finite numbers or trailing content are allowed. JSON is data:
do not parse it with load, loadfile, LuaEx.deserialize or executable Lua.

Required top-level properties:

| Property | Type | Meaning |
| --- | --- | --- |
| Schema | integer | 1 |
| Kind | string | game, set, ui, graphics or animation |
| UUID | string | Logical package UUID in lowercase canonical form |
| Title | string | Human-readable display title, 1..256 UTF-8 bytes |
| Entries | array | Entry records in physical payload order |

Optional properties:

| Property | Type | Meaning |
| --- | --- | --- |
| GameUUID | string | Required for ui/graphics/animation; target game's UUID |
| Thumbnail | string | Path of an embedded PNG entry |
| Description | string | Up to 4096 UTF-8 bytes |

For game packages, UUID is the game UUID and MUST match the archive filename.
For set packages, UUID is the CFS set UUID and MUST match the archive filename.
For overrides, UUID identifies the override package and GameUUID identifies the
game it overrides. A standalone set is not forced to belong to only one game.

UUIDs use exactly 8-4-4-4-12 hexadecimal digits separated by hyphens. Version bits
are not constrained by this format. Readers MUST compare parsed UUIDs rather
than relying on filename casing.

Unknown top-level properties are rejected in 1.0; future versions must specify
extension handling. There is no embedded gameplay schema or assumed Lua entry
point in this container version. Those belong to separate, versioned package
content contracts.

Each Entries record has exactly:

| Property | Type | Meaning |
| --- | --- | --- |
| Path | string | Unique relative virtual path |
| Offset | integer | Byte offset relative to payload start |
| Size | integer | Plaintext size |
| CipherSize | integer | Size + 16 |
| Nonce | string | 48 lowercase hex characters encoding 24 nonce bytes |

Integers MUST be mathematically integral, nonnegative and within the bounds
below. Never coerce JSON strings to numbers or round oversized values.

The first entry has Offset 0. Every later Offset equals the preceding Offset
plus CipherSize. Final offset plus final CipherSize MUST equal PayloadSize.
Reject duplicates, gaps, overlap, out-of-range regions and unreferenced bytes.
A package has at least one entry. Zero-length files are allowed and still have
a 16-byte authentication tag. CFA 1.0 does not compress entries.

Thumbnail, if present, MUST exactly name an entry. It is encrypted like any
other file. A reader MUST authenticate its bytes before decoding the image and
apply image dimension/memory limits before presenting it. Discovery may decrypt
only the index and thumbnail without reading every other file.

## 6. Virtual paths

Paths are platform-independent, case-insensitively unique and relative.
For this first version, entry paths use ASCII letters, digits, underscores,
hyphens, dots and forward slashes only. Human-readable metadata remains UTF-8;
Unicode entry paths would require a later normalization contract.

Reject leading/trailing slashes, empty components, backslashes, drive names,
absolute paths, colon characters, NUL bytes, "." or ".." components, components
ending in a dot, and Windows device basenames CON, PRN, AUX, NUL, COM1..COM9
and LPT1..LPT9, including those names before a file extension.
A component is at most 128 bytes; a complete path is at most 1024 bytes.
Use ASCII lowercase solely as the duplicate-detection key; retain original bytes
for authentication and display. Paths do not refer to the host filesystem.

No archive entry represents a symlink, hard link, device or directory. Empty
directories are not stored. Normal operation reads entries in memory and MUST
NOT automatically extract them to disk. Any later explicit extraction feature
must separately enforce filesystem containment and link checks.

## 7. Bounds and failure behavior

CFA 1.0 format limits:

- Whole file: at most 64 GiB (68,719,476,736 bytes).
- Decrypted index: at most 16 MiB (16,777,216 bytes).
- Entries: 1..65,535.
- Single plaintext entry: at most 256 MiB (268,435,456 bytes).
- JSON nesting: at most 16 levels.
- Decoded thumbnail: at most 2048 by 2048 pixels and 16 MiB RGBA memory.

IndexCipherSize is at least 16 and at most 16,777,232. Readers MUST bound work
and memory before allocation; a small malformed file must not cause a huge
allocation. Consumers may impose lower documented operational limits, but MUST
report the limit as the reason rather than misidentify a valid file as corrupt.

Failures need distinct categories: unsupported format, bounds exceeded, missing
key, authentication failure, malformed index, missing entry and I/O failure.
Never expose unauthenticated partial plaintext. Do not execute any Lua while
opening, authenticating, listing or reading an archive. Loading game scripts is
an explicit later engine operation, with its own trust and execution policy.

A corrupt game should produce a per-game discovery diagnostic. Other installed
games should remain discoverable. Readers MUST NOT fall back to treating a
failed encrypted package as a directory or plain Lua script.

## 8. Writer and reader contracts

The implementation should expose separate operations for:

- Opening and authenticating an index using a supplied key resolver.
- Inspecting authenticated metadata and enumerating entry paths.
- Reading and authenticating one named entry without extraction.
- Verifying every entry when a complete integrity check is requested.
- Closing a reader and releasing handles and native secret buffers.
- Exporting a new package with new key material and a matching key-provider record.

Write a new archive to a temporary sibling file, close and validate it, then
publish it without silently overwriting an existing package. Do not serialize
keys into the archive, application logs, diagnostic messages or source control.
No actual production keys or sample credentials are defined by this document.

## 9. Compatibility and implementation gates

Readers and writers must agree on this exact version. New header meanings,
cryptography, compression, index schema or path normalization require an
explicit format revision. Do not guess or quietly accept newer formats.

Before claiming CFA 1.0 support, ship:

1. A reviewed native crypto binding and JSON parser with the limits above.
2. A reader, writer and automatic key-provider deployment implementation.
3. An independently produced byte-level interoperability vector.
4. Round-trip checks for every package kind and optional thumbnail.
5. Rejection tests for altered headers/indexes/entries, wrong or missing keys,
   truncation, unsupported versions, duplicate paths, unsafe paths and limits.
6. Discovery tests proving one bad package does not hide other games.

Gameplay semantics, publisher signatures, automatic updating, networking and
asset licensing remain separate contracts. This draft changes no runtime
behavior and creates no packages or keys.

## 10. Cryptographic references

- XChaCha20-Poly1305 combined mode and associated data:
  https://doc.libsodium.org/secret-key_cryptography/aead/chacha20-poly1305/xchacha20-poly1305_construction
- Cryptographically secure random bytes:
  https://doc.libsodium.org/generating_random_data

These references define cryptographic primitives, not an endorsement or
independent security review of this new container design.