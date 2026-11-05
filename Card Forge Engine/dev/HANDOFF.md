# Card Forge Engine handoff

Updated: 2026-11-04. Read before continuing implementation.
This records confirmed discussion, current code and limitations separately.

## Working rules

- Obtain explicit permission before editing; only edit the authorized files.
  The current session authorized framework work, plugin installation and this handoff.
- Product/API name is Card Forge Engine / CardForgeEngine. Project folder stays CFE.
- Application behavior is Lua/LuaEx; native code is limited to runtime/hosting.
- Use wxWidgets/wxLua/wxLuma for the UI; prefer wxLuma where applicable.
- Root init.lua remains the native launch entry. Application code lives in Scripts,
  organized by purpose: Windows, Pages, Controls, Services, Engine, Plugins, Tests.
- Native source and CMake files belong in Src. App binaries belong in Bin/Windows,
  Bin/Mac and Bin/Linux. Vendor-required runtime layouts are preserved unchanged.
- Follow LuaEx's GitHub README naming/formatting conventions: PascalCase classes
  and exported modules, camelCase methods, typed variable prefixes, underscore
  prefixes for file-scoped locals. A local function gets f only inside another
  function. Class-instance parameters use other. Class methods use dot calls.
- Use meaningful DOx comments and local explanatory comments; keep code modular,
  readable, editable and generously spaced. Do not create monolithic source.
- Before changing LuaEx itself, follow the user's requirement to understand the
  entire framework, disclose understanding gaps and ask before such changes.
  No complete-understanding claim has been made. Vendor source is unchanged.
- User performs visual checks. Automated native smoke tests are appropriate.
- Keep downloads, toolchains, build caches and fixtures out of the project and
  clean owned temporary staging after success. No agent delegation was requested.

## Product roles and authoring decisions

- CFS = Card Forge Studio: code-based card designer; not a gameplay engine.
- CFA = Card Forge Architect: authors games against the API defined by CFE.
- CFE = Card Forge Engine: supplies generic runtime systems and enforces rules.
- Assume Lua knowledge; Lua tutorials are outside product scope.
- Gameplay declarations belong in CFA, not CFS. CFS exports designed cards/sets;
  CFA defines decks and game rules. A CFS exporter for this ecosystem is future work.
- CFS sets already have UUIDs. Preserve those IDs in exported set packages.
- Commercial closed-source games are an intended use. Authors may also share
  projects voluntarily. Protection discourages casual extraction; do not promise
  that shipped client assets or keys cannot be recovered.
- Networking, standalone/client/server/hosting export profiles were discussed;
  none of those runtime or export systems is implemented yet.

## Confirmed game-system foundation

- Use LuaEx's class system, with the engine API in namespace CardForgeEngine.
- Reuse CoG foundations where appropriate. Extend CoG.BaseCard as needed rather
  than assuming it already implements the complete card-game runtime.
- Participant is called Actor.
- Generic engine activities are Operations. Game-specific actions such as
  sacrifice compose generic Operations such as movement.
- Operation callbacks go onto resolution stacks; there are multiple independent
  stacks per game, with last-in, first-out order.
- The game explicitly chooses which stack resolves next. Engine behavior is
  fixed, so builders do not have to implement the engine or micromanage checks.
- CFA supplies stable card instance identity. Resolve IDs against current state
  when an Operation executes, not only when it is queued.
- Builders declare card conditions. The engine checks existence and every
  declared condition immediately before running the user callback.
- Invalid Operations skip and report a reason automatically, with no player
  confirmation or manual validation. This implementation also records failures.
- Modifier means a lasting change to properties, rules or permitted actions.
  It can conceptually affect cards, Actors, zones or the game; not implemented.
- A lasting modification differs from a triggered behavior. Trigger, Effect and
  the suggested name Pop were discussed; that lexicon is NOT finalized.
- Cards need add/remove, draws and pile placement, ordering, placement over/under
  cards, and permanent/temporary transfers between Actors.
- Rotation has eight stopping orientations N, NE, E, SE, S, SW, W, NW, 45 degrees
  apart; clockwise/counterclockwise movement and direct orientation were discussed.
- Revealing/concealing, flipping, searching, shuffling, attachments, properties,
  targeting and copying were discussed as generic activities, not implemented.
- Distinguish an ordered card pile from a resolution stack. Whether over/under
  creates an attachment, ownership versus control, temporary-transfer expiry,
  Actor/zone APIs, turns/phases and response windows still need concrete contracts.

## Implemented engine code

Scripts/Engine:
- Cards/Card.lxc: CardForgeEngine.Card extends CoG.BaseCard; adds read-only ID.
- Operations/Operation.lxc: immutable captured requirement records and callback,
  live lookup/checks, single-use resolution, structured outcomes.
- Stacks/Stack.lxc: CardForgeEngine.Stack extends LuaEx.Classes.Stack; validated
  Operation push, inherited stack storage, reversal prohibited.
- Game/Game.lxc: card presence/identity registry, named stacks, explicit one-item
  dispatch, cross-stack reentrancy guard and private dispatch permits.
- README.md: current API examples, exact behavior and important limitations.

Callbacks receive (game, cardsByID); requirements use CardID plus optional Check.
Check receives (card, game) and must return true, or false/nil plus optional reason.
Predicates must be synchronous and side-effect-free. All dependent cards must be
declared: the engine cannot infer arbitrary Lua closure dependencies.
Result statuses: Resolved, Skipped, Failed, Empty. Game.getResults returns copied
records for the latest 128 nonempty resolutions. No automatic whole-stack drain.
A consumed Operation cannot run twice, including after a skipped/failed attempt.
Callbacks may enqueue new work; recursive resolution is rejected.

This foundation is NOT a sandbox or transaction engine. Callback errors do not
undo earlier changes. Native LuaEx clone/serialization of complete game sessions
and queued closures has not been validated or designed as a save-file contract.
No Move Operation, piles/zones, Actors, Modifiers, rotation or turn systems yet.

## Plugins and startup

Scripts/Plugins/LuaEx:
- https://github.com/CentauriSoldier/LuaEx
- Installed revision b587e3c925a6b0b2e0f49abb76194d96eaf1c7cf.
- 101 runtime files compared byte-for-byte with upstream; unchanged.
- Native filesystem binaries keep their required upstream bin layout.
- Native sources/build files copied to Src/Plugins/LuaEx/src.

Scripts/Plugins/cog (lowercase folder is required by upstream module names):
- https://github.com/CentauriSoldier/CoG
- Installed revision 31a5143b37331ec43fb0cda21d28273937d211fe.
- 53 runtime files compared byte-for-byte with upstream; unchanged.
- Existing CoG.BaseCard, BaseDeck, RNG, Shuffler and other systems are available.
- RNG uses math.random; never use it for archive encryption keys.
- CoG.load initializes configuration; simply discovering classes is not enough
  before constructing configuration-dependent cards/objects.

Scripts/Bootstrap.lua sets the plugin search paths, requires LuaEx.init, then
calls require("cog.load")(), loads wxLuma and opens Scripts/Windows/Main.lua.
LuaEx auto-discovers .lxc/.lxe declarations through package.path; CFE classes
do not have ordinary Lua require aliases. Use fully qualified class names.

## Current application and game discovery

- Root Card Forge Engine.lnk launches Bin/Windows/Card Forge Engine.exe.
- Native launcher/CMake/resource files: Src/Launcher.
- Root init.lua dispatches Scripts/Bootstrap.lua.
- One native application frame; no inner skinned window.
- Blue space-engine card artwork: Images/Card Forge Engine.png.
- Multi-size icon: Bin/Windows/Card Forge Engine.ico; embedded in EXE and set
  on the native frame. The root shortcut uses that embedded icon.
- Welcome artwork/introduction retains its original layout. Games is a separate
  far-right image/text ListEx column. Redundant footer text is removed.
- Main window default is 1400x720 to accommodate that extra column.
- GameDiscovery in Scripts/Services uses LuaEx I/O and home directory, not Documents.
- Default library: ~/Card Forge Engine. Scanning does not create the directory.
- One UUID.cfa at the root of each direct child game folder identifies a candidate.
  Sets is inventoried when present; Decks.lua and override archives are optional.
- Records include UUID, Title from folder, Directory, Archive, Sets, Decks,
  Overrides. Image remains unset until authenticated package metadata is readable.
- Scan failures and ambiguity are separate diagnostics; Main retains
  DiscoveryIssues. A diagnostics UI is not implemented.
- Discovery does not decrypt, validate or execute archive/script contents.

## CFA archive decisions and draft standard

CFA means Card Forge Archive here (distinct from Card Forge Architect).
The format standard is Docs/Formats/CFA-1.0.md. It is a DRAFT, not implemented.
Do not claim current discovery can open these encrypted containers.

Agreed on-disk layout:

    ~/Card Forge Engine/
        MyGame/
            <game-uuid>.cfa
            Sets/
                <set-uuid>.cfa
            Decks.lua
            UIO.cfa
            GEO.cfa
            AO.cfa

- Keep the readable game folder name; name the GAME ARCHIVE with its UUID.
- Game rules stay inside that game archive.
- Sets holds UUID-named card sets exported from CFS.
- Decks.lua holds shipped/prebuilt decks and supports user-created decks under
  game-defined deck-building rules. It is explicitly outside encrypted archives.
- UIO/GEO/AO are optional UI, graphical-effects and animation overrides.
- Dedicated encrypted container, not ZIP. Automatic opening with a shipped key;
  no player password prompt.
- Protect metadata, index, filenames, artwork, scripts and content; only a minimal
  identification/unlock header stays readable.
- Use established authenticated encryption; custom file format is not cryptography.
- The draft specifies a 128-byte header, encrypted JSON index, independently
  authenticated entries, XChaCha20-Poly1305-IETF, random per-export 32-byte keys,
  24-byte nonces and 16-byte tags.
- KeyID is a lookup ID, not a key. No universal engine secret. Actual key-provider
  carrier/export deployment remains to be implemented, not invented as finished.
- Draft package kinds: game, set, ui, graphics, animation.
- Draft defines safe paths, limits, header/index/entry authentication, explicit
  failure categories and version rejection. CFA 1.0 has no compression.
- LuaEx I/O handles filesystem operations; its ZIP helpers do not provide this
  custom encrypted CFA format and are not to be substituted for it.
- Crypto binding, JSON parser, reader/writer, key provider, interoperability
  vectors and security rejection tests are ALL still pending.
- Native crypto would belong to the runtime; application logic remains Lua.
- A shipped key can be recovered; authenticated encryption is not publisher
  signatures, server authority, licensing enforcement or an execution sandbox.

## Existing Windows runtime and verification

Windows x64 is built and operational:
- Lua 5.4.8, wxWidgets 3.2.12, wxLua 3.2.0.2.
- Src/BuildWindows.ps1 rebuilds dependencies; launcher is a separate build.
- Src/Launcher/CMakeLists.txt is the conventional launcher build.
- Src/Launcher/Build.cmake supports an installed Zig compiler via explicit path.
- App runtime dependencies and build-info are in Bin/Windows.
- Mac/Linux native builds were deferred; corresponding Bin folders are reserved.
- Src/README.md documents source builds, launcher and runtime verification.

Passed during this framework task:
- CoG startup and BaseCard/RNG checks.
- Scripts/Tests/Framework.lua: inheritance, independent LIFO stacks, stable IDs,
  requirement snapshots, missing cards, current-state predicates, registry changes,
  condition/callback errors, reentrancy, dispatch-only execution, single-use
  Operations, copied/bounded diagnostics.
- Card Forge Engine.exe --smoke with LuaEx, CoG, new classes and welcome UI.
- CoG source hash comparison; owned download staging removed.

Earlier discovery fixture tests passed before this framework change. They have
not been rerun with reconstructed fixtures during this task. Mac/Linux, visual
layout, networking, crypto and archive interoperability were not verified.

## Next work

Discuss and implement small, generic systems against these foundations:
Actor, zone/pile ownership and ordering, movement and identity lifecycle, rotation,
transfer/expiry, Modifier lifetime and event/trigger terminology. Reuse CoG where
its documented behavior fits, but do not import game-specific defaults as universal
engine rules. Resolve transactional behavior before complex multi-card operations.

Keep the handoff current as decisions change. Do not present suggested terminology,
unimplemented archive support or future export features as completed behavior.