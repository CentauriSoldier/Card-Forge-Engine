--[[!
@fqxn CardForgeEngine.Tests.Framework
@desc Native regression checks for CoG integration and the first engine classes.
    Uses only isolated in-memory games; no installed games or user files change.
!]]
local _pRoot = assert(arg[1], "Supply the Card Forge Engine installation root.");
package.path = _pRoot.."/?.lua;".._pRoot.."/?/init.lua;"
    .._pRoot.."/Scripts/Plugins/?.lua;".._pRoot.."/Scripts/Plugins/?/init.lua";
require("LuaEx.init");
require("cog.load")();

local _oGame  = CardForgeEngine.Game();
local _oCard  = CardForgeEngine.Card("card-1", "Test card");
local _oOther = CardForgeEngine.Card("card-2", "Other card");
_oGame.addCard(_oCard).addCard(_oOther);
local _oMain  = _oGame.createStack("main");
local _oReply = _oGame.createStack("reply");
local _tOrder = {};

assert(class.isa(_oCard, "CoG.BaseCard"));
assert(class.getparentname("CardForgeEngine.Stack") == "LuaEx.Classes.Stack");
assert(CoG.RNG.binary(0) == 0 and CoG.RNG.binary(1) == 1);
assert(not pcall(_oMain.push, function() end), "Bare callbacks must not bypass validation.");
assert(not pcall(_oMain.reverse), "Resolution stacks cannot reverse.");
assert(not pcall(_oGame.createStack, "main"), "Stack names must be unique.");
assert(not pcall(_oGame.addCard, CardForgeEngine.Card("card-1")), "IDs cannot be reassigned.");

_oMain.push(CardForgeEngine.Operation("first", function()
    _tOrder[#_tOrder + 1] = "first";
end));
_oMain.push(CardForgeEngine.Operation("second", function()
    _tOrder[#_tOrder + 1] = "second";
end));
_oReply.push(CardForgeEngine.Operation("reply", function()
    _tOrder[#_tOrder + 1] = "reply";
end));
assert(_oGame.resolveNext("main").Status == "Resolved");
assert(_oReply.size() == 1, "Resolving one stack must leave another alone.");
assert(_oGame.resolveNext("reply").Status == "Resolved");
assert(_oGame.resolveNext("main").Status == "Resolved");
assert(table.concat(_tOrder, ",") == "second,reply,first", "Stacks must resolve LIFO by explicit selection.");
assert(_oGame.resolveNext("main").Status == "Empty");

local _bRan = false;
local _oMissing = CardForgeEngine.Operation("missing", function()
    _bRan = true;
end, {{CardID = "card-1"}});
_oMain.push(_oMissing);
_oGame.removeCard("card-1");
assert(_oGame.resolveNext("main").Code == "CardMissing" and not _bRan);
_oGame.addCard(_oCard);

local _tRequirement = {{CardID = "card-1", Check = function(other)
    return other.isFaceUp(), "Card must be face up.";
end}};
local _oChecked = CardForgeEngine.Operation("condition", function()
    _bRan = true;
end, _tRequirement);
-- Editing the caller's records must not silently remove registered rules.
_tRequirement[1].Check = nil;
_oMain.push(_oChecked);
local _tRejected = _oGame.resolveNext("main");
assert(_tRejected.Status == "Skipped" and _tRejected.Code == "ConditionRejected" and not _bRan);

local _oDelayed = CardForgeEngine.Operation("current state", function(other, tCards)
    assert(other == _oGame and tCards["card-1"] == _oCard);
    _bRan = true;
end, {{CardID = "card-1", Check = function(other) return other.isFaceUp(); end}});
_oMain.push(_oDelayed);
_oCard.reveal();
assert(_oGame.resolveNext("main").Status == "Resolved" and _bRan);

_oMain.push(CardForgeEngine.Operation("condition error", function() error("Must not run."); end,
    {{CardID = "card-1", Check = function() error("Predicate failed."); end}}));
assert(_oGame.resolveNext("main").Code == "ConditionError");
_oMain.push(CardForgeEngine.Operation("callback error", function() error("Callback failed."); end));
assert(_oGame.resolveNext("main").Code == "CallbackError");

_oMain.push(CardForgeEngine.Operation("changed registry", function() error("Must not run."); end,
    {{CardID = "card-1", Check = function()
        _oGame.removeCard("card-1");
        return true;
    end}}));
assert(_oGame.resolveNext("main").Code == "CardChanged");
_oGame.addCard(_oCard);

_oMain.push(CardForgeEngine.Operation("reentrant", function()
    _oGame.resolveNext("reply");
end));
assert(_oGame.resolveNext("main").Code == "CallbackError");
_oMain.push(CardForgeEngine.Operation("after error", function() end));
assert(_oGame.resolveNext("main").Status == "Resolved", "Resolution lock must recover after errors.");

local _oDirect = CardForgeEngine.Operation("direct", function() error("Must not run."); end);
assert(not pcall(_oDirect.resolve, _oGame), "User code cannot resolve outside a stack dispatch.");
_oMain.push(_oDelayed);
assert(_oGame.resolveNext("main").Code == "AlreadyResolved", "Resolved Operations cannot execute twice.");
local _tResults = _oGame.getResults();
assert(#_tResults > 0);
_tResults[1].Status = "changed";
assert(_oGame.getResults()[1].Status ~= "changed", "History must be copied.");

-- Bounded diagnostics do not grow without limit during a long-running game.
for nIndex = 1, 140 do
    _oMain.push(CardForgeEngine.Operation("bounded", function() end));
    assert(_oGame.resolveNext("main").Status == "Resolved");
end
assert(#_oGame.getResults() == 128);
print("PASS: CoG cards/RNG, LuaEx inheritance, independent LIFO stacks, validation, stale cards, failure isolation, dispatch enforcement and bounded reports.");