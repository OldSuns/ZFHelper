param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string[]]$PublishedTags = @()
)

$ErrorActionPreference = 'Stop'

if ($Tag -cnotmatch '^lxy-v([0-9]+\.[0-9]+\.[0-9]+)$') {
    throw 'LXY releases require a tag named lxy-vX.Y.Z.'
}
$tagVersion = $Matches[1]
$manifest = Get-Content -LiteralPath 'pubspec.yaml' -Raw -Encoding UTF8
$version = [regex]::Match($manifest, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
if (-not $version.Success -or $version.Groups[1].Value -cne $tagVersion) {
    throw 'The LXY tag must match pubspec.yaml version X.Y.Z+build.'
}
$buildNumber = [long]$version.Groups[2].Value
if ($buildNumber -lt 1 -or $buildNumber -gt 2100000000) {
    throw 'The Android build number must be between 1 and 2100000000.'
}

$tagCommit = git rev-parse --verify "$Tag^{commit}"
if ($LASTEXITCODE -ne 0) { throw 'The release tag must already exist.' }
$headCommit = git rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $headCommit -cne $tagCommit) {
    throw 'The checkout must match the release tag.'
}
git merge-base --is-ancestor $headCommit origin/LXY
if ($LASTEXITCODE -ne 0) {
    throw 'LXY release tags must point at commits reachable from origin/LXY.'
}

foreach ($publishedTag in $PublishedTags) {
    if ($publishedTag -ceq $Tag) {
        throw 'This release is already published; publish a new version instead.'
    }
    if ($publishedTag -cnotmatch '^(?:lxy-)?v[0-9]+\.[0-9]+\.[0-9]+(?:-(?:dev|beta|rc)\.[0-9]+)?$') {
        throw "Unrecognized published tag: $publishedTag"
    }
    $publishedManifest = git show "${publishedTag}:pubspec.yaml"
    if ($LASTEXITCODE -ne 0) { throw "Cannot read published tag $publishedTag." }
    $publishedVersion = [regex]::Match(($publishedManifest -join "`n"), '(?m)^version:\s*\S+\+([0-9]+)\s*$')
    if (-not $publishedVersion.Success) {
        throw "Cannot determine the Android build number for $publishedTag."
    }
    if ($buildNumber -le [long]$publishedVersion.Groups[1].Value) {
        throw "The build number must exceed published release $publishedTag."
    }
    if ($publishedTag.StartsWith('lxy-v', [StringComparison]::Ordinal) -and
        [version]$tagVersion -le [version]$publishedTag.Substring(5)) {
        throw "The LXY version must exceed published release $publishedTag."
    }
}

Write-Output "Validated LXY $tagVersion+$buildNumber."
