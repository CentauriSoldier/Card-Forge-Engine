# Card Forge Engine foundation

These are native LuaEx LXC classes in the CardForgeEngine namespace. LuaEx
discovers .lxc sources through the application package.path at initialization.
Do not require .lxc files as ordinary Lua modules or create short global aliases.

## Files

- Cards/Card.lxc: extends CoG.BaseCard with a stable, read-only instance ID.
- Operations/Operation.lxc: captures a callback and card requirements, then
  validates current state immediately before the engine invokes the callback.
- Stacks/Stack.lxc: extends LuaEx.Classes.Stack with validated push and fixed LIFO.
- Game/Game.lxc: card presence, named stacks, controlled dispatch and diagnostics.

Bootstrap places Scripts/Plugins on package.path, initializes LuaEx, calls
require("cog.load")(), then creates the application window. CFE does not replace
or modify either vendor framework. LuaEx's class system discovers CoG and CFE
declarations together so inheritance dependencies are available.

## Basic use

After the frameworks initialize:

    local oGame = CardForgeEngine.Game();
    local oCard = CardForgeEngine.Card("CFA-supplied-instance-id", "Example");
    oGame.addCard(oCard);
    local oStack = oGame.createStack("main");

    oStack.push(CardForgeEngine.Operation("Reveal", function(other, tCards)
        tCards["CFA-supplied-instance-id"].reveal();
    end, {
        {
            CardID = "CFA-supplied-instance-id",
            Check = function(other)
                return not other.isFaceUp(), "Card is already face up.";
            end,
        },
    }));

    local tResult = oGame.resolveNext("main");

Class methods use dot calls. This Operation captures a function; its
requirements identify live cards by ID instead of retaining queued card objects.
The engine performs every check before entering the user function. Check must
return literal true to permit execution; false/nil returns Skipped automatically.
Requirements are copied when queued work is constructed. Predicates MUST be
synchronous and side-effect-free. They do not prompt a player.

Every card a callback depends on must be declared in its requirements. Lua
closures are not inspected to infer hidden card dependencies. Empty requirements
are valid for operations that do not reference cards. Do not yield from rules
or callbacks; this first resolver is synchronous and does not implement waits.

## Stack behavior

Games may create any number of independent named stacks. Game.resolveNext(name)
processes exactly one top item on the selected stack. There is no automatic
scheduler, hidden stack selection or response/priority window yet.

Stack.push accepts Operation instances, not bare functions. reverse is rejected.
Inherited peek, size, iteration, pop and clear retain LuaEx behavior; pop/clear
remove pending work without executing it. Execution is exclusively through
Game.resolveNext. A private per-dispatch permit prevents direct Operation.resolve
calls. Reentrant resolveNext is rejected across this game's stacks, but callbacks
may push later work. This is an engine API contract, not a sandbox against code
using debug access to attack the runtime.

An Operation is consumed on its first resolution attempt, even when skipped or
failed. Reusing that same object produces AlreadyResolved; construct a fresh
Operation for a deliberate retry. No whole-stack automatic drain is provided.

## Results and errors

Results have Status, Code, Stack and, for an actual Operation, Operation.
Reason is provided for skips/errors. Status is Resolved, Skipped, Failed or Empty.

- Completed: callback returned normally.
- CardMissing: required card no longer exists in this game.
- ConditionRejected: a declared condition did not return true.
- CardChanged: a predicate changed a required registry entry.
- ConditionError: condition raised an error; user callback was not run.
- CallbackError: user callback raised an error.
- AlreadyResolved: the same Operation has already been consumed.
- ResolverError: unexpected dispatch error.
- StackEmpty: selected stack has no work.

A normal callback return, including false, is not an engine failure. It must
raise an error to signal failure after validation. Failed callbacks may already
have changed state: this first foundation does not provide atomic transactions
or rollback. Game.getResults returns copies of the most recent 128 nonempty
resolution reports. Invalid API use, such as an unknown stack, fails explicitly.

Card IDs belong to one identity within a Game. Removing a card removes presence;
the same instance may return. Another instance cannot reuse that ID in the game.
The same ID may exist in separate game contexts. Cross-game transfer semantics
have not been defined. IDs are currently nonempty strings; no card-instance UUID
encoding is assumed before CFA defines it.

## Current scope

CoG already supplies generic card metadata, tags, presentation flags, deck,
shuffling and RNG foundations. RNG uses math.random and is NOT suitable for
archive keys. CFE's Card currently adds identity only. Game-specific card
subclasses must implement their own clone policy; inheriting CoG.BaseCard's
plain-card clone does not support cloning a subclass.

Actors, zones/piles, movement, eight-direction rotation, ownership/control,
Modifiers, triggers/effects, turns, targeting and networking are not implemented.
The framework does not yet load or execute CFA archives. Do not expose direct
CoG presentation mutators as permission-checked gameplay Operations by accident.

## Verification

From the installation root:

    & "./Bin/Windows/lua.exe" "./Scripts/Tests/Framework.lua" (Get-Location).Path
    & "./Bin/Windows/Card Forge Engine.exe" --smoke

Framework.lua uses in-memory games only; it does not edit the home game library.