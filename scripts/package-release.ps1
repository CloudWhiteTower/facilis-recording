param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$Ref = 'HEAD'
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a semantic release version' }
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$applicationPath = Join-Path $repositoryRoot 'HarmonyRecorder\build\outputs\default\HarmonyRecorder-default-unsigned.app'
$distributionPath = Join-Path $repositoryRoot ('dist\v' + $Version)
Add-Type -AssemblyName System.IO.Compression.FileSystem

# The source archive comes from Git, never from the local signed working tree.
$sourceManifestText = & git -C $repositoryRoot show ($Ref + ':HarmonyRecorder/AppScope/app.json5')
if ($LASTEXITCODE -ne 0) { throw 'Git source revision is unavailable' }
$sourceManifest = ($sourceManifestText -join "`n") | ConvertFrom-Json
if ($sourceManifest.app.versionName -ne $Version) { throw 'Source revision has a different version' }

New-Item -ItemType Directory -Path $distributionPath -Force | Out-Null
$prefix = 'facilis-recording-v' + $Version
$hapPath = Join-Path $distributionPath ($prefix + '-release-unsigned.hap')
$appZipPath = Join-Path $distributionPath ($prefix + '-release-unsigned-app.zip')
$sourceZipPath = Join-Path $distributionPath ($prefix + '-source.zip')
$application = [IO.Compression.ZipFile]::OpenRead($applicationPath)
try {
  $modules = @($application.Entries | Where-Object { $_.FullName -match '\.hap$' })
  if ($modules.Count -ne 1) { throw 'Expected exactly one HAP in the final unsigned APP' }
  [IO.Compression.ZipFileExtensions]::ExtractToFile($modules[0], $hapPath, $true)
} finally { $application.Dispose() }

$hap = [IO.Compression.ZipFile]::OpenRead($hapPath)
try {
  $reader = [IO.StreamReader]::new($hap.GetEntry('module.json').Open())
  try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
  if ($manifest.app.versionName -ne $Version -or $manifest.app.debug -ne $false) {
    throw 'Expected a Release HAP matching the source version'
  }
  foreach ($entry in @('libs/arm64-v8a/libfacilis_flac.so', 'libs/x86_64/libfacilis_flac.so',
    'resources/rawfile/LLVM-NOTICE.txt')) {
    if ($null -eq $hap.GetEntry($entry)) { throw ('Missing release content: ' + $entry) }
  }
} finally { $hap.Dispose() }

if (Test-Path -LiteralPath $appZipPath) { Remove-Item -LiteralPath $appZipPath }
$appZip = [IO.Compression.ZipFile]::Open($appZipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($appZip, $applicationPath,
    ($prefix + '-release-unsigned.app'), [IO.Compression.CompressionLevel]::Optimal) | Out-Null
} finally { $appZip.Dispose() }
& git -C $repositoryRoot archive --format=zip ('--output=' + $sourceZipPath) $Ref
if ($LASTEXITCODE -ne 0) { throw 'Source archive failed' }

$sourceZip = [IO.Compression.ZipFile]::OpenRead($sourceZipPath)
try {
  $privateEntries = @($sourceZip.Entries | Where-Object {
    $_.FullName -match '(^|/)(\.codex|\.hvigor|\.cxx|oh_modules|build|design-reference-local)/' -or
    $_.FullName -match '\.(p12|pfx|jks|keystore|key|pem|cer|csr|p7b|wav|flac|m4a|pcm)$'
  })
  if ($privateEntries.Count -gt 0) { throw 'Source archive contains private/build/audio material' }
  $reader = [IO.StreamReader]::new($sourceZip.GetEntry('HarmonyRecorder/build-profile.json5').Open())
  try { $profile = $reader.ReadToEnd() } finally { $reader.Dispose() }
  if ($profile -match '"(certpath|profile|storeFile|keyPassword|storePassword)"\s*:\s*"[^"\s]+"') {
    throw 'Tracked build profile contains local signing material'
  }
} finally { $sourceZip.Dispose() }

$checksums = foreach ($file in @($hapPath, $appZipPath, $sourceZipPath)) {
  (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($file)
}
[IO.File]::WriteAllLines((Join-Path $distributionPath 'SHA256SUMS.txt'), $checksums, [Text.UTF8Encoding]::new($false))
Write-Output ('Prepared unsigned release v' + $Version + ' in ' + $distributionPath)
