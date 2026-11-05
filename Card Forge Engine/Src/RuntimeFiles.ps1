<#
.SYNOPSIS
Stages and installs the Windows dependency runtime.
.DESCRIPTION
Only compiler-produced runtime files are copied. PE imports determine the
portable compiler DLL closure. Installation retains rollback copies in the
owned temporary build folder until the final native verification succeeds.
#>

<#
@fqxn CFE.Build.NewRuntimeCandidate
@desc Collects matching Lua, wxLua, wxWidgets and their non-system DLL dependencies.
@param string Stage Owned temporary source/build folder.
@param string CompilerBin Verified portable compiler's bin directory.
@return string Candidate folder containing only runtime artifacts.
#>
function New-RuntimeCandidate {
    param([string]$Stage, [string]$CompilerBin)

    $candidate = Join-Path $Stage 'runtime'
    if (Test-Path -LiteralPath $candidate) {
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $stageRoot = [System.IO.Path]::GetFullPath($Stage).TrimEnd('\', '/')
        if ($resolved -ne (Join-Path $stageRoot 'runtime') -or
            -not $resolved.StartsWith($stageRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Runtime cleanup target is outside the owned temporary build.'
        }
        $items = @(Get-Item -LiteralPath $resolved) + @(Get-ChildItem -LiteralPath $resolved -Recurse -Force)
        if ($items | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint }) {
            throw 'Runtime staging contains a filesystem link.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    New-Item -ItemType Directory -Path $candidate -ErrorAction Stop | Out-Null
    $wxLibrary = Join-Path $Stage 'wx-build/lib/clang_x64_dll'
    Get-ChildItem -LiteralPath $wxLibrary -Filter '*.dll' -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $candidate }
    foreach ($relative in @('lua-install/lua54.dll', 'lua-install/lua.exe',
        'wxlua-build/bin/Release/wx.dll', 'wx-build/lib/clang_x64_dll/wxrc.exe')) {
        Copy-Item -LiteralPath (Join-Path $Stage $relative) -Destination $candidate -ErrorAction Stop
    }

    # Check every PE, including extra wx libraries not loaded by the smoke test.
    $pending = [System.Collections.Generic.Queue[string]]::new()
    Get-ChildItem -LiteralPath $candidate -File | ForEach-Object { $pending.Enqueue($_.FullName) }
    $checked = @{}
    while ($pending.Count -gt 0) {
        $path = $pending.Dequeue()
        if ($checked.ContainsKey($path)) { continue }
        $checked[$path] = $true
        $imports = & (Join-Path $CompilerBin 'llvm-readobj.exe') --coff-imports $path
        if ($LASTEXITCODE -ne 0) { throw ('Cannot inspect PE imports: ' + $path) }
        foreach ($line in $imports) {
            if ($line -notmatch '^\s*Name: (.+\.dll)$') { continue }
            $name = $Matches[1]
            if ($name -match '^(api-ms-|ext-ms-)') { continue }
            $installed = Join-Path $candidate $name
            if (Test-Path -LiteralPath $installed) { continue }
            if (Test-Path -LiteralPath (Join-Path $env:SystemRoot ('System32/' + $name))) { continue }
            $compilerLibrary = Join-Path $CompilerBin $name
            if (-not (Test-Path -LiteralPath $compilerLibrary)) {
                throw ('Missing non-system dependency: ' + $name + ' imported by ' + $path)
            }
            Copy-Item -LiteralPath $compilerLibrary -Destination $installed
            $pending.Enqueue($installed)
        }
    }
    return $candidate
}

<#
@fqxn CFE.Build.TestRuntimeCandidate
@desc Runs the native verification with PATH limited to the candidate and Windows.
@param string Root CFE application root containing the bundled wxLuma framework.
@param string Candidate Runtime folder under test.
#>
function Test-RuntimeCandidate {
    param([string]$Root, [string]$Candidate)

    $previousPath = $env:PATH
    $previousLuaInit = $env:LUA_INIT
    $previousLuaInitVersion = $env:LUA_INIT_5_4
    try {
        $env:PATH = $Candidate + ';' + $env:SystemRoot + '/System32;' + $env:SystemRoot
        $env:LUA_INIT = ''
        $env:LUA_INIT_5_4 = ''
        & (Join-Path $Candidate 'lua.exe') (Join-Path $Root 'Src/VerifyRuntime.lua') $Root $Candidate
        if ($LASTEXITCODE -ne 0) { throw 'Native dependency runtime verification failed.' }
    }
    finally {
        $env:PATH = $previousPath
        $env:LUA_INIT = $previousLuaInit
        $env:LUA_INIT_5_4 = $previousLuaInitVersion
    }
}

<#
@fqxn CFE.Build.InstallRuntimeCandidate
@desc Replaces only owned runtime artifacts and restores the old set on failure.
@param string Root Authorized CFE root.
@param string Stage Owned temporary folder used for rollback copies.
@param string Candidate Verified new runtime files.
@param object Lock Pinned dependency metadata for the installed build record.
#>
function Install-RuntimeCandidate {
    param([string]$Root, [string]$Stage, [string]$Candidate, $Lock)

    $destination = Join-Path $Root 'Bin/Windows'
    $backup = Join-Path $Stage ('previous-runtime-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
    $manifestPath = Join-Path $destination 'build-info.json'
    $previousNames = @()
    if (Test-Path -LiteralPath $manifestPath) {
        $oldManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $previousNames = @($oldManifest.runtimeFiles | ForEach-Object { $_.name })
        Copy-Item -LiteralPath $manifestPath -Destination $backup
    }

    # Recognize the originally supplied MSVC runtime by its exact naming family.
    $oldFiles = @(Get-ChildItem -LiteralPath $destination -File | Where-Object {
        $_.Name -in $previousNames -or $_.Name -match '(_vc_x64_custom\.dll$|^wx\.dll$|^lua54\.dll$|^MSVCP140\.dll$|^VCRUNTIME140(?:_1)?\.dll$)'
    })
    foreach ($file in $oldFiles) { Copy-Item -LiteralPath $file.FullName -Destination $backup }
    $newFiles = @(Get-ChildItem -LiteralPath $Candidate -File)

    try {
        foreach ($file in $newFiles) { Copy-Item -LiteralPath $file.FullName -Destination $destination -Force }
        foreach ($file in $oldFiles) {
            if ($file.Name -notin $newFiles.Name) { Remove-Item -LiteralPath $file.FullName -Force }
        }
        Test-RuntimeCandidate -Root $Root -Candidate $destination
        $records = @($newFiles | ForEach-Object {
            [ordered]@{name = $_.Name; sha256 = (Get-FileHash -LiteralPath (Join-Path $destination $_.Name)).Hash.ToLowerInvariant()}
        })
        $manifest = [ordered]@{
            platform = 'Windows'; architecture = 'x86_64'; configuration = 'Release'
            lua = $Lock.lua.version; wxWidgets = $Lock.wxWidgets.version
            wxLua = $Lock.wxLua.version; wxLuaRevision = $Lock.wxLua.revision
            compiler = 'llvm-mingw-' + $Lock.compiler.version
            debugLevel = 0; webviewBackend = 'IE'; webviewEdge = $false
            verification = 'Native paint, wxLuma, STC/AUI, events, state and shutdown passed with isolated PATH.'
            runtimeFiles = $records
        }
        [System.IO.File]::WriteAllText($manifestPath,
            ($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        # Remove new-only files, then restore all original files and provenance.
        foreach ($file in $newFiles) {
            if ($file.Name -notin $oldFiles.Name) {
                $path = Join-Path $destination $file.Name
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $backup 'build-info.json')) -and
            (Test-Path -LiteralPath $manifestPath)) {
            Remove-Item -LiteralPath $manifestPath -Force
        }
        Get-ChildItem -LiteralPath $backup -File |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destination -Force }
        throw
    }
}

<#
@fqxn CFE.Build.InstallRuntimeNotices
@desc Retains supplied upstream license notices alongside the runtime binaries.
@param string Root Authorized CFE root.
@param string Stage Verified temporary source/tool folder.
@param object Lock Pinned versions used to resolve source folders.
#>
function Install-RuntimeNotices {
    param([string]$Root, [string]$Stage, $Lock)

    $destination = Join-Path $Root 'Bin/Windows/Licenses'
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $wxRoot = Join-Path $Stage 'wxWidgets'
    Get-ChildItem -LiteralPath $wxRoot -File -Recurse | Where-Object {
        $_.Name -match '^(licen[cs]e.*|copying.*|copyright.*|gpl\.txt|lgpl\.txt)$'
    } | ForEach-Object {
        $name = 'wxWidgets-' + [System.IO.Path]::GetRelativePath($wxRoot, $_.FullName).Replace('\', '-').Replace('/', '-')
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destination $name) -Force
    }
    $compilerRoot = Join-Path $Stage ('compiler/llvm-mingw-' + $Lock.compiler.version + '-ucrt-x86_64')
    Copy-Item -LiteralPath (Join-Path $compilerRoot 'LICENSE.TXT') -Destination (Join-Path $destination 'LLVM-MinGW.txt') -Force
    Get-ChildItem -LiteralPath (Join-Path $compilerRoot 'x86_64-w64-mingw32/share/mingw32') -File |
        Where-Object { $_.Name -like 'COPYING*' } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destination ('MinGW-' + $_.Name)) -Force }
    Copy-Item -LiteralPath (Join-Path $Stage ('wxlua/wxlua-' + $Lock.wxLua.revision + '/wxLua/docs/licence.txt')) -Destination (Join-Path $destination 'wxLua.txt') -Force
    Copy-Item -LiteralPath (Join-Path $Stage ('lua-' + $Lock.lua.version + '/README')) -Destination (Join-Path $destination 'Lua-README.txt') -Force

    # Some bundled codec projects keep their notice in README rather than LICENSE.
    foreach ($relative in @('src/jpeg/README', 'src/zlib/README', '3rdparty/nanosvg/README.md')) {
        $path = Join-Path $wxRoot $relative
        if (Test-Path -LiteralPath $path) {
            Copy-Item -LiteralPath $path -Destination (Join-Path $destination ('wxWidgets-' + $relative.Replace('/', '-'))) -Force
        }
    }
}
