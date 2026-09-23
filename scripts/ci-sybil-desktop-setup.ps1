$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$version = (Get-Content .fvmrc | ConvertFrom-Json).flutter
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid Flutter version' }
$bootstrap = Join-Path $env:RUNNER_TEMP 'flutter-bootstrap'
git clone --depth 1 --branch $version https://github.com/flutter/flutter.git $bootstrap
$env:PUB_CACHE = Join-Path $env:RUNNER_TEMP 'pub-cache'
$flutterBin = Join-Path $bootstrap 'bin'
$pubBin = Join-Path $env:PUB_CACHE 'bin'
$env:PATH = "$flutterBin$([IO.Path]::PathSeparator)$pubBin$([IO.Path]::PathSeparator)$env:PATH"
"PUB_CACHE=$env:PUB_CACHE" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
$flutterBin, $pubBin | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8
flutter --version
dart pub global activate fvm 4.3.0
fvm install $version
$rust = (Get-Content scripts/release-config/android-reproducible-rust-version.txt).Trim()
if ($rust -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid Rust version' }
rustup toolchain install $rust --profile minimal
"RUSTUP_TOOLCHAIN=$rust", "VIZOR_RUST_TOOLCHAIN=$rust" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
