# Native dependency builds

These scripts build Lua 5.4.8, wxWidgets 3.2.12 and wxLua 3.2.0.2 together.
They do not implement a Card Forge Engine game API. The separate launcher build is documented below.

## Files

- BuildWindows.ps1: checked Windows x64 build, verification and cleanup.
- Dependencies.json: official source/tool URLs, versions and SHA-256 pins.
- Lua/CMakeLists.txt: shared Lua library and command-line interpreter.
- WxLua/CMakeLists.txt: upstream build wrapper, module naming and matching assertion ABI.
- RuntimeFiles.ps1: PE dependency closure, isolated testing and rollback-safe replacement.
- VerifyRuntime.lua: native wxLuma/rendering/events/state/STC/AUI/shutdown test.
- Patches/wxWidgets-algorithm.txt: documents required direct standard-header includes.

## Build on Windows

Run with PowerShell 7 and installed CMake:

    .\Src\BuildWindows.ps1

The default CMake path is C:\Program Files\CMake\bin\cmake.exe. Override it with
-CMake when necessary; -Jobs controls compiler parallelism.

The build downloads a portable LLVM-MinGW toolchain and Ninja without changing
system installations. Downloads, extracted source, object files and rollback
copies live in one marked OS temporary folder. Success removes that folder.
Failed jobs identify their temporary folder for diagnosis; -ResumeStage can
resume one only when its ownership marker matches this CFE root.

## Installed runtime

Bin/Windows contains the matched runtime DLLs, lua.exe and wxrc.exe.
Compiler/import libraries and headers are build inputs, not runtime dependencies.
Upstream notices are retained in Bin/Windows/Licenses. build-info.json records
installed versions, configuration and individual artifact hashes.

The initial MSVC DLL set is replaced as one tested dependency set. It is not mixed
with the new LLVM-MinGW libraries. New builds have their wxWidgets DLL vendor
suffix set to cfe, and wxLua uses the same release assertion ABI (wxDEBUG_LEVEL=0).

All 14 supported wxLua binding groups are enabled. The wxWidgets libraries also
include their additional native QA and ribbon components. WebView is built with
the IE backend; the Edge/WebView2 backend is not enabled in this toolchain build.

## Verify the installed runtime

    .\Bin\Windows\lua.exe .\Src\VerifyRuntime.lua . .\Bin\Windows

The build script performs the same check with PATH restricted to the runtime
folder and Windows system directories, excluding compiler and previous DLL paths.
It inspects PE imports for every shipped EXE/DLL, not just the smoke-test module.

## Other platforms

Mac and Linux builds have not been performed. Their existing Bin folders are
reserved. Native platform toolchains/build machines are needed for those jobs.
The current task was narrowed to completing the local Windows build first.

## Windows application launcher

The root shortcut Card Forge Engine.lnk starts Bin/Windows/Card Forge Engine.exe.
The executable resolves the installation from its own location and executes root
init.lua. Scripts/Bootstrap.lua loads the bundled wxLuma and opens the initial
window. Application behavior stays in Lua; Launcher/main.c only hosts Lua,
forwards arguments, selects local DLLs and reports startup errors.

Launcher/CMakeLists.txt is the conventional native C build, separate from
BuildWindows.ps1. With a Windows C compiler and generator available, configure
and build into an OS temporary directory, then copy Card Forge Engine.exe to Bin/Windows:

    cmake -S Src/Launcher -B "$env:TEMP/CFE-launcher"
    cmake --build "$env:TEMP/CFE-launcher" --config Release

The executable may be under Release with a multi-configuration generator.
Remove that temporary build directory after copying the executable.

Alternatively, Launcher/Build.cmake supports an installed Zig C compiler:

    cmake "-DZIG_EXECUTABLE=C:/path/to/zig.exe" "-DSTAGING_DIR=$env:TEMP/CFE-launcher" -P Src/Launcher/Build.cmake

Copy the resulting Card Forge Engine.exe to Bin/Windows and remove the temporary directory.
Neither route downloads a compiler or stores caches inside the project.

For a self-closing startup check, run & "./Bin/Windows/Card Forge Engine.exe" --smoke.
It opens the bundled wxLuma window, checks startup and forwarded arguments,
closes the window and writes Bin/Windows/launcher-check.txt on success.
Startup failures return a nonzero exit code and append card-forge-engine-error.log beside
the executable. Interactive failures also display a native error dialog.
Launcher/CardForgeEngine.rc embeds Bin/Windows/Card Forge Engine.ico in the EXE.
The Lua bootstrap also sets this icon on the native application window.

Application Lua modules live in Scripts: Bootstrap.lua owns startup, Windows/Main.lua owns the native frame, and Pages/Welcome.lua owns the welcome page. Root init.lua remains the launcher entry. Bundled wxLuma stays self-contained.
