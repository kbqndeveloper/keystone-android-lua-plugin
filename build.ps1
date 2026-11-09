param(
    [int]$Jobs = 4
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$AndroidHome = $env:ANDROID_HOME
if ([string]::IsNullOrWhiteSpace($AndroidHome)) {
    throw '请先设置 ANDROID_HOME。'
}

if ($env:ANDROID_NDK_HOME) {
    $Ndk = $env:ANDROID_NDK_HOME
} else {
    $Ndk = Join-Path $AndroidHome 'ndk\android-ndk-r23c'
}
$CmakeBin = Join-Path $AndroidHome 'cmake\3.22.1\bin'
$Cmake = Join-Path $CmakeBin 'cmake.exe'
$Ninja = Join-Path $CmakeBin 'ninja.exe'
$Strip = Join-Path $Ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-strip.exe'
$Toolchain = Join-Path $Ndk 'build\cmake\android.toolchain.cmake'

foreach ($Required in @($Cmake, $Ninja, $Strip, $Toolchain)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        throw "找不到构建工具：$Required"
    }
}

# Keystone's bundled LLVM CMake does not handle non-ASCII source paths reliably on Windows.
$DriveLetter = @('Z', 'Y', 'X', 'W', 'V', 'U', 'T', 'S', 'R', 'Q') |
    Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) } |
    Select-Object -First 1
if (-not $DriveLetter) {
    throw '没有可用于构建的临时盘符（Z: 到 Q: 均已占用）。'
}
$Drive = "${DriveLetter}:"
& "$env:WINDIR\System32\subst.exe" $Drive $Root
if ($LASTEXITCODE -ne 0) {
    throw "无法创建临时构建盘符 $Drive。"
}

$env:PATH = "$CmakeBin;$env:PATH"
try {
    foreach ($Abi in @('arm64-v8a', 'x86_64')) {
        $BuildDir = Join-Path $Drive "build\$Abi"
        $OutputDir = Join-Path $Root "package\keystone\$Abi"
        $ConfigureLog = Join-Path $Root "build\$Abi-configure.log"
        $BuildLog = Join-Path $Root "build\$Abi-build.log"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigureLog), $OutputDir | Out-Null

        $ConfigureArgs = @(
            '-S', (Join-Path $Drive 'src'),
            '-B', $BuildDir,
            '-G', 'Ninja',
            "-DCMAKE_MAKE_PROGRAM=$Ninja",
            "-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $Ndk 'build\cmake\android.toolchain.cmake')",
            "-DANDROID_ABI=$Abi",
            '-DANDROID_PLATFORM=android-23',
            '-DLLVM_TARGETS_TO_BUILD=AArch64;X86',
            '-DLLVM_USE_HOST_TOOLS=OFF',
            '-DLLVM_ENABLE_PIC=ON',
            '-DLLVM_ENABLE_TERMINFO=OFF',
            '-DLLVM_ENABLE_ZLIB=OFF',
            '-DLLVM_ENABLE_LIBEDIT=OFF',
            '-DBUILD_SHARED_LIBS=ON',
            '-DBUILD_LIBS_ONLY=ON',
            '-DCMAKE_BUILD_TYPE=MinSizeRel',
            '-Wno-dev'
        )

        & $Cmake @ConfigureArgs *> $ConfigureLog
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $ConfigureLog -Tail 80
            throw "Keystone $Abi 配置失败。"
        }

        & $Cmake --build $BuildDir --target keystone --parallel $Jobs *> $BuildLog
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $BuildLog -Tail 100
            throw "Keystone $Abi 编译失败。"
        }

        $BuiltLibrary = Join-Path $BuildDir 'llvm\lib\libkeystone.so'
        $FinalLibrary = Join-Path $OutputDir 'libkeystone.so'
        if (-not (Test-Path -LiteralPath $BuiltLibrary -PathType Leaf)) {
            throw "编译完成但没有找到动态库：$BuiltLibrary"
        }
        Copy-Item -LiteralPath $BuiltLibrary -Destination $FinalLibrary -Force
        & $Strip --strip-unneeded $FinalLibrary
        if ($LASTEXITCODE -ne 0) {
            throw "Keystone $Abi 符号精简失败。"
        }

        $SizeMb = [math]::Round((Get-Item -LiteralPath $FinalLibrary).Length / 1MB, 2)
        Write-Host ("{0}: {1} MB -> {2}" -f $Abi, $SizeMb, $FinalLibrary)
    }
} finally {
    & "$env:WINDIR\System32\subst.exe" $Drive /D | Out-Null
}
