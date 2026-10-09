param(
  [Parameter(Mandatory = $true)][string]$SourceDirectory,
  [string]$Version = '3.0.2'
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a semantic version' }
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputDirectory = [IO.Path]::GetFullPath((Join-Path $repositoryRoot ('data\store-assets-v' + $Version)))
if (!$outputDirectory.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar,
  [StringComparison]::OrdinalIgnoreCase)) { throw 'Asset output escaped repository' }
Add-Type -AssemblyName System.Drawing
$sources = @('recorder', 'player', 'conversion', 'privacy')
$targets = @(
  @{ Name = 'phone'; Width = 1080; Height = 1920 },
  @{ Name = 'tablet'; Width = 1280; Height = 1920 }
)
foreach ($target in $targets) {
  $directory = Join-Path $outputDirectory $target.Name
  New-Item -ItemType Directory -Path $directory -Force | Out-Null
  foreach ($name in $sources) {
    $sourcePath = Join-Path $SourceDirectory ($name + '-portrait.png')
    if (!(Test-Path -LiteralPath $sourcePath)) { throw ('Missing final screenshot: ' + $sourcePath) }
    $source = [Drawing.Image]::FromFile($sourcePath)
    $canvas = [Drawing.Bitmap]::new($target.Width, $target.Height, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    try {
      $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#FFF9F3'))
      $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      # Fit the complete captured interface. Never crop, stretch, invent controls or alter recorded text.
      $scale = [Math]::Min(($target.Width - 32) / $source.Width, ($target.Height - 32) / $source.Height)
      $width = [Math]::Round($source.Width * $scale)
      $height = [Math]::Round($source.Height * $scale)
      $rectangle = [Drawing.Rectangle]::new([Math]::Floor(($target.Width - $width) / 2),
        [Math]::Floor(($target.Height - $height) / 2), $width, $height)
      $graphics.DrawImage($source, $rectangle)
      $path = Join-Path $directory ($name + '.png')
      $canvas.Save($path, [Drawing.Imaging.ImageFormat]::Png)
      if ((Get-Item -LiteralPath $path).Length -gt 5MB) { throw ('Screenshot exceeds market size limit: ' + $path) }
    } finally { $graphics.Dispose(); $canvas.Dispose(); $source.Dispose() }
  }
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'docs\assets\icon-preview.png') -Destination (Join-Path $directory 'icon.png') -Force
}
Write-Output ('Prepared complete, unstretched interface canvases in ' + $outputDirectory)
