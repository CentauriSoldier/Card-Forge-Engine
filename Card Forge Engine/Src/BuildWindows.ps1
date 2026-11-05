<#
.SYNOPSIS
Builds the Windows x64 Lua, wxWidgets and wxLua runtime from pinned sources.
.DESCRIPTION
Downloads verified sources and portable tools to an owned temporary folder.
The application folder receives only source build scripts and the verified
runtime. A failed native build never replaces the installed DLLs.
.PARAMETER Jobs
Maximum parallel compiler jobs. Default is eight.
.PARAMETER CMake
Path to an installed CMake executable.
.PARAMETER ResumeStage
An owned temporary folder from an interrupted build; its marker must match CFE.
#>
param(
    [ValidateRange(1, 32)][int]$Jobs = 8,
    [string]$CMake = 'C:\Program Files\CMake\bin\cmake.exe',
    [string]$ResumeStage
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Dependencies.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'RuntimeFiles.ps1')

<#
@fqxn CFE.Build.GetVerifiedArchive
@desc Downloads an official archive and checks its pinned SHA-256 before extraction.
#>
function Get-VerifiedArchive {
    param($Record, [string]$Name)
    $path = Join-Path $stage $Name
    if (-not (Test-Path -LiteralPath $path)) { Invoke-WebRequest -Uri $Record.url -OutFile $path }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Record.sha256) {
        throw ('Source/tool checksum mismatch: ' + $Name)
    }
    return $path
}

<#
@fqxn CFE.Build.InvokeCMake
@desc Runs one checked CMake step, retaining full compiler output only in staging.
#>
function Invoke-CMake {
    param([string]$Name, [string[]]$Arguments)
    Write-Host $Name
    $log = Join-Path $stage ($Name + '.log')
    & $CMake @Arguments *> $log
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $log -Tail 35
        throw ($Name + ' failed; diagnostic log: ' + $log)
    }
}

<#
@fqxn CFE.Build.RemoveOwnedStage
@desc Deletes only a marked CFE build directory strictly inside the OS temp folder.
#>
function Remove-OwnedStage {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') + '\'
    $marker = Join-Path $resolved '.cfe-build-owned'
    if (-not $resolved.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [System.IO.Path]::GetFileName($resolved).StartsWith('CFE-wx-build-') -or
        -not (Test-Path -LiteralPath $marker) -or
        [System.IO.File]::ReadAllText($marker) -ne $root) {
        throw 'Temporary cleanup target failed ownership checks.'
    }
    $items = @(Get-Item -LiteralPath $resolved) + @(Get-ChildItem -LiteralPath $resolved -Recurse -Force)
    if ($items | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint }) {
        throw 'Temporary build contains a filesystem link; refusing recursive cleanup.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

if (-not (Test-Path -LiteralPath $CMake)) { throw 'Supply an installed CMake executable.' }
if ($ResumeStage) {
    $stage = [System.IO.Path]::GetFullPath($ResumeStage)
    $marker = Join-Path $stage '.cfe-build-owned'
    if (-not (Test-Path -LiteralPath $marker) -or [System.IO.File]::ReadAllText($marker) -ne $root) {
        throw 'ResumeStage is not an owned build folder for this CFE installation.'
    }
} else {
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('CFE-wx-build-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $stage '.cfe-build-owned'), $root)
}
$previousPath = $env:PATH
$completed = $false

try {
    foreach ($entry in @(
        @{Record=$lock.compiler; Name='compiler.zip'; Folder='compiler'},
        @{Record=$lock.ninja; Name='ninja.zip'; Folder='ninja'},
        @{Record=$lock.wxWidgets; Name='wxWidgets.zip'; Folder='wxWidgets'},
        @{Record=$lock.wxLua; Name='wxlua.zip'; Folder='wxlua'}
    )) {
        $archive = Get-VerifiedArchive -Record $entry.Record -Name $entry.Name
        $folder = Join-Path $stage $entry.Folder
        if (-not (Test-Path -LiteralPath $folder)) { Expand-Archive -LiteralPath $archive -DestinationPath $folder }
    }
    $luaArchive = Get-VerifiedArchive -Record $lock.lua -Name 'lua.tar.gz'
    if (-not (Test-Path -LiteralPath (Join-Path $stage ('lua-' + $lock.lua.version)))) {
        & tar.exe -xzf $luaArchive -C $stage
        if ($LASTEXITCODE -ne 0) { throw 'Lua extraction failed.' }
    }

    # CMake resource-compiler paths must use forward slashes.
    $s = $stage.Replace('\', '/')
    $compiler = "$s/compiler/llvm-mingw-$($lock.compiler.version)-ucrt-x86_64/bin"
    $env:PATH = $compiler + ';' + $env:PATH
    $common = @('-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$s/ninja/ninja.exe",
        "-DCMAKE_C_COMPILER=$compiler/x86_64-w64-mingw32-clang.exe",
        "-DCMAKE_CXX_COMPILER=$compiler/x86_64-w64-mingw32-clang++.exe",
        "-DCMAKE_RC_COMPILER:FILEPATH=$compiler/x86_64-w64-mingw32-windres.exe",
        '-DCMAKE_BUILD_TYPE=Release')

    # Current libc++ requires the direct standard include described in Patches/.
    foreach ($relative in @('src/stc/scintilla/src/XPM.cxx', 'src/stc/scintilla/src/SplitVector.h')) {
        $path = "$s/wxWidgets/$relative"
        $text = [System.IO.File]::ReadAllText($path)
        if (-not $text.Contains('#include <algorithm>')) {
            $position = $text.IndexOf('#include')
            if ($position -lt 0) { $position = $text.IndexOf('#ifndef') }
            if ($position -lt 0) { throw 'Cannot locate compatibility-header insertion point.' }
            $text = $text.Insert($position, '#include <algorithm>' + [Environment]::NewLine + [Environment]::NewLine)
            [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
        }
    }

    Invoke-CMake 'configure-lua' (@('-S', "$PSScriptRoot/Lua", '-B', "$s/lua-build") + $common +
        @("-DLUA_SOURCE_DIR=$s/lua-$($lock.lua.version)/src", "-DCMAKE_INSTALL_PREFIX=$s/lua-install"))
    Invoke-CMake 'build-lua' @('--build', "$s/lua-build", '--parallel', "$Jobs")
    Invoke-CMake 'install-lua' @('--install', "$s/lua-build")

    Invoke-CMake 'configure-wx' (@('-S', "$s/wxWidgets", '-B', "$s/wx-build") + $common +
        @('-DwxBUILD_SHARED=ON', '-DwxBUILD_MONOLITHIC=OFF', '-DwxBUILD_PRECOMP=OFF',
          '-DwxBUILD_SAMPLES=OFF', '-DwxBUILD_TESTS=OFF', '-DwxBUILD_DEMOS=OFF',
          '-DwxBUILD_DEBUG_LEVEL=0', '-DwxBUILD_VENDOR=cfe',
          '-DwxBUILD_USE_STATIC_RUNTIME=OFF', '-DwxUSE_WEBVIEW_EDGE=OFF',
          '-DwxUSE_WEBVIEW_IE=ON', "-DCMAKE_INSTALL_PREFIX=$s/wx-install"))
    Invoke-CMake 'build-wx' @('--build', "$s/wx-build", '--parallel', "$Jobs")

    $components = 'webview;gl;xrc;xml;net;media;propgrid;richtext;aui;stc;html;adv;core;base'
    Invoke-CMake 'configure-wxlua' (@('-S', "$PSScriptRoot/WxLua", '-B', "$s/wxlua-build") + $common +
        @('-DBUILD_SHARED_LIBS=ON', '-DCMAKE_POLICY_VERSION_MINIMUM:STRING=3.5',
          "-DWXLUA_SOURCE_DIR=$s/wxlua/wxlua-$($lock.wxLua.revision)/wxLua",
          "-DwxWidgets_ROOT_DIR=$s/wxWidgets", "-DwxWidgets_LIB_DIR=$s/wx-build/lib/clang_x64_dll",
          '-DwxWidgets_VERSION:STRING=3.2.12', '-DwxWidgets_CONFIGURATION=mswu',
          '-DwxWidgets_USE_STATIC=OFF', '-DwxWidgets_USE_REL_AND_DBG=OFF', '-DwxWidgets_USE_DEBUG=OFF',
          "-DwxWidgets_COMPONENTS=$components", "-DwxLuaBind_COMPONENTS=$components",
          '-DwxLua_LUA_LIBRARY_USE_BUILTIN=OFF', '-DwxLua_LUA_LIBRARY_VERSION:STRING=5.4',
          '-DwxLua_LUA_LIBRARY_BUILD_SHARED=ON', "-DwxLua_LUA_INCLUDE_DIR=$s/lua-$($lock.lua.version)/src",
          "-DwxLua_LUA_LIBRARY=$s/lua-install/lib/liblua54.dll.a"))
    Invoke-CMake 'build-wxlua' @('--build', "$s/wxlua-build", '--target', 'wxLuaModule', '--parallel', "$Jobs")

    $candidate = New-RuntimeCandidate -Stage $stage -CompilerBin $compiler
    Test-RuntimeCandidate -Root $root -Candidate $candidate
    Install-RuntimeCandidate -Root $root -Stage $stage -Candidate $candidate -Lock $lock
    Install-RuntimeNotices -Root $root -Stage $stage -Lock $lock
    $completed = $true
}
finally {
    $env:PATH = $previousPath
    # Failed jobs retain a clearly identified OS-temp folder for diagnosis.
    # A successful build removes downloads, tools, sources, caches and rollback.
    if ($completed) { Remove-OwnedStage -Path $stage }
    else { Write-Warning ('Build staging retained for diagnosis: ' + $stage) }
}
Write-Host 'Windows x64 runtime built, verified and installed. Temporary build files removed.'
