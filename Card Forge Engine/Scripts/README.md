# Application scripts

- Bootstrap.lua initializes LuaEx, wxLua and wxLuma, then runs the application.
- Windows/Main.lua owns the frame and populates its Games list.
- Pages/Welcome.lua owns the welcome content and layout.
- Controls/GamesList.lua configures wxLuma ListEx with image and title columns.
- Services/GameDiscovery.lua inventories installed games using LuaEx I/O.
- Plugins/LuaEx contains the unmodified upstream runtime, including its required
  native modules in the upstream bin layout. UPSTREAM.json pins the revision.
  Native build sources are under Src/Plugins/LuaEx/src.
- Tests/GameDiscovery.lua checks discovery against an isolated fixture library.

## Game discovery

The library is the user's home directory plus Card Forge Engine. Discovery does
not create it. Each game follows the agreed layout:

    ~/Card Forge Engine/
        MyGame/
            <game-uuid>.cfa
            Sets/
                <set-uuid>.cfa
            Decks.lua
            UIO.cfa
            GEO.cfa
            AO.cfa

A game folder keeps its readable name. Exactly one UUID-named CFA at the root
identifies the game. Sets is inventoried when present. Decks.lua and the UI,
graphical-effects and animation override archives are optional; discovery never
loads them or executes their code.

GameDiscovery.scan() returns games and a separate diagnostics array. An optional
library path supports isolated tests and future library selection. Only direct
child game folders and direct Sets entries are examined. Every call rescans disk.
Ambiguous game folders are excluded; invalid set archive names are reported.
A missing library is an empty result; other filesystem failures are diagnostics.
Window.DiscoveryIssues retains the startup diagnostics for a future library UI.

Returned records have UUID, Title (folder name), Directory, Archive, Sets, Decks
and Overrides. Archive contents are not inspected or validated yet. Image stays
unset until the package metadata/artwork contract is defined; GamesList already
accepts an Image path when that metadata becomes available.

Bootstrap adds Scripts/Plugins to package.path and requires LuaEx.init before
application widgets capture globals. Vendor files are unchanged. Windows
initialization, native filesystem I/O and application startup have been tested;
other platforms have not been tested here.

The discovery fixture test takes installation root and fixture-library root as
arguments. It expects Alpha (with one valid and one invalid set, Decks.lua and
all overrides), Zulu (uppercase UUID archive), Ambiguous (two UUID archives),
Unrelated/Nested (nested-only archive), and WrongArchive (Game.cfa). It adds and
removes one archive inside WrongArchive to check fresh snapshots.
## Game-system foundation

Engine/README.md documents the CardForgeEngine LXC classes. Plugins/cog supplies unchanged CoG foundations; Bootstrap initializes its configuration after LuaEx. Tests/Framework.lua verifies the first resolution API. See ../dev/HANDOFF.md for confirmed decisions, CFA archive plans and implementation limits.
