--[[!
@fqxn CFE.Build.VerifyRuntime
@desc Verifies newly built Lua/wxWidgets/wxLua binaries against the bundled
    wxLuma framework. This is a dependency test, not a CFE gameplay API.
    The test owns its native frame, components, skin and wx event loop.
!]]
local pRoot = assert(arg[1], "Supply the CFE root.");
local pBin = assert(arg[2], "Supply the candidate runtime folder.");
pRoot, pBin = pRoot:gsub("\\", "/"), pBin:gsub("\\", "/");
package.path = pRoot.."/?.lua;"..pRoot.."/?/init.lua";
package.cpath = pBin.."/?.dll";

local wx = require("wx");
local wxLuma = require("wxLuma")();
local Controls = wxLuma.Controls;
local oSkin = Controls.loadSkin();
local nClicks, nChanges = 0, 0;
local oFrame = wx.wxFrame(wx.NULL, wx.wxID_ANY, "CFE runtime verification",
    wx.wxDefaultPosition, wx.wxSize(640, 460));
local oButton = Controls.button(oFrame, {
    Skin = oSkin, Text = "Runtime verification",
    OnClick = function() nClicks = nClicks + 1; end,
});
local oField = Controls.textfield(oFrame, {
    Skin = oSkin, Value = "Initial",
    OnChange = function() nChanges = nChanges + 1; end,
});
oButton.layout(24, 24, 220, 40);
oField.layout(270, 24, 280, 40);
assert(wxstc and wxstc.wxStyledTextCtrl and wxaui and wxaui.wxAuiManager,
    "Styled text or AUI bindings are missing.");
local oEditor = wxstc.wxStyledTextCtrl(oFrame, wx.wxID_ANY);
oEditor:SetSize(24, 90, 540, 280);
oEditor:SetLexer(wxstc.wxSTC_LEX_LUA);
oEditor:SetText("-- Runtime verification\nlocal nValue = 3;\n");

local sFailure;
local oTimer = wx.wxTimer(oFrame);
oFrame:Connect(oTimer:GetId(), wx.wxEVT_TIMER, function()
    oTimer:Stop();
    local bOK, sError = xpcall(function()
        assert(oFrame:IsShown(), "Native frame was not shown.");
        assert(oSkin.getBitmap("Button Left Normal"):IsOk(), "Bundled skin failed.");
        oButton.handleKey("down", wx.WXK_RETURN);
        oButton.handleKey("up", wx.WXK_RETURN);
        assert(nClicks == 1, "Button callback did not fire exactly once.");
        oField.TextControl:SetValue("Native change");
        assert(nChanges == 1, "Native text callback did not fire exactly once.");
        local tState = oField.getObjectState();
        oField.setValue("Changed");
        oField.setObjectState(tState);
        assert(oField.getValue() == "Native change", "Object-state round trip failed.");
        assert(oEditor:GetText():find("nValue", 1, true), "Styled editor content failed.");
    end, debug.traceback);
    if (not bOK) then sFailure = sError; end
    oFrame:Close();
end);
oFrame:Connect(wx.wxEVT_CLOSE_WINDOW, function(oEvent)
    oButton.destroy();
    oField.destroy();
    oSkin.destroy();
    oEvent:Skip();
end);
oFrame:Show(true);
oTimer:Start(300, true);
wx.wxGetApp():MainLoop();
collectgarbage("collect");
assert(not sFailure, sFailure);
print("PASS: ".._VERSION.."; "..tostring(wx.wxVERSION_STRING));
print("PASS: wxLuma loading/artwork, native paint, button/text events, state, STC, AUI and shutdown.");
