param(
  [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-RoundedRectanglePath {
  param(
    [float]$X,
    [float]$Y,
    [float]$Width,
    [float]$Height,
    [float]$Radius
  )

  $diameter = $Radius * 2
  $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
  $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
  $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
  $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
  $path.CloseFigure()
  return $path
}

function Save-Png {
  param(
    [System.Drawing.Bitmap]$Bitmap,
    [string]$Path
  )

  $directory = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $directory -Force | Out-Null
  $temporaryPath = "$Path.new.png"
  $Bitmap.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Png)
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$assetDirectory = Join-Path $RepositoryRoot 'docs\assets'
$backgroundPath = Join-Path $assetDirectory 'facilis-icon-background.png'
$foregroundPath = Join-Path $assetDirectory 'facilis-icon-foreground.png'
$previewPath = Join-Path $assetDirectory 'icon-preview.png'

$background = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$backgroundGraphics = [System.Drawing.Graphics]::FromImage($background)
# HarmonyOS layered-icon backgrounds must be a solid, fully opaque color.
# RGB storage also prevents alpha from being introduced by resource optimization.
$backgroundGraphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#F58720'))
Save-Png -Bitmap $background -Path $backgroundPath
$backgroundGraphics.Dispose()

$foreground = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$foregroundGraphics = [System.Drawing.Graphics]::FromImage($foreground)
$foregroundGraphics.Clear([System.Drawing.Color]::Transparent)
$foregroundGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$foregroundGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$foregroundGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$markColor = [System.Drawing.ColorTranslator]::FromHtml('#FFF7EF')
$markBrush = [System.Drawing.SolidBrush]::new($markColor)

$waveBars = @(
  @(188, 440, 48, 144),
  @(252, 390, 48, 244),
  @(316, 430, 48, 164),
  @(660, 430, 48, 164),
  @(724, 390, 48, 244),
  @(788, 440, 48, 144)
)

foreach ($bar in $waveBars) {
  $barPath = New-RoundedRectanglePath -X $bar[0] -Y $bar[1] -Width $bar[2] -Height $bar[3] -Radius 24
  $foregroundGraphics.FillPath($markBrush, $barPath)
  $barPath.Dispose()
}

$microphonePath = New-RoundedRectanglePath -X 386 -Y 190 -Width 252 -Height 400 -Radius 126
$foregroundGraphics.FillPath($markBrush, $microphonePath)
$microphonePath.Dispose()

$foregroundGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$clearBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Transparent)
$cutouts = @(
  @(452, 346, 22, 104),
  @(500, 300, 24, 196),
  @(550, 346, 22, 104)
)
foreach ($cutout in $cutouts) {
  $cutoutPath = New-RoundedRectanglePath -X $cutout[0] -Y $cutout[1] -Width $cutout[2] -Height $cutout[3] -Radius 11
  $foregroundGraphics.FillPath($clearBrush, $cutoutPath)
  $cutoutPath.Dispose()
}
$clearBrush.Dispose()
$foregroundGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver

$supportPen = [System.Drawing.Pen]::new($markColor, 54)
$supportPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$supportPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$foregroundGraphics.DrawArc($supportPen, 310, 350, 404, 404, 0, 180)
$foregroundGraphics.DrawLine($supportPen, 512, 754, 512, 842)
$basePen = [System.Drawing.Pen]::new($markColor, 58)
$basePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$basePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$foregroundGraphics.DrawLine($basePen, 410, 842, 614, 842)

Save-Png -Bitmap $foreground -Path $foregroundPath
$basePen.Dispose()
$supportPen.Dispose()
$markBrush.Dispose()
$foregroundGraphics.Dispose()

$preview = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$previewGraphics = [System.Drawing.Graphics]::FromImage($preview)
$previewGraphics.DrawImageUnscaled($background, 0, 0)
$previewGraphics.DrawImageUnscaled($foreground, 0, 0)
Save-Png -Bitmap $preview -Path $previewPath
$previewGraphics.Dispose()
$preview.Dispose()
$background.Dispose()
$foreground.Dispose()

$projectMediaDirectories = @(
  (Join-Path $RepositoryRoot 'HarmonyRecorder\AppScope\resources\base\media'),
  (Join-Path $RepositoryRoot 'HarmonyRecorder\entry\src\main\resources\base\media')
)

foreach ($mediaDirectory in $projectMediaDirectories) {
  Copy-Item -LiteralPath $backgroundPath -Destination (Join-Path $mediaDirectory 'background.png') -Force
  Copy-Item -LiteralPath $foregroundPath -Destination (Join-Path $mediaDirectory 'foreground.png') -Force
}

Copy-Item -LiteralPath $foregroundPath -Destination (
  Join-Path $RepositoryRoot 'HarmonyRecorder\entry\src\main\resources\base\media\startIcon.png'
) -Force

Write-Output "Generated HarmonyOS layered icon assets in $assetDirectory"
