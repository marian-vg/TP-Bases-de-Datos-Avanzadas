[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._-]+\))?!?: .+')]
    [string]$Message,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Paths
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

$branch = (& git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne 'dev/simulacion') {
    throw "Atomic feature commits are allowed only on dev/simulacion. Current branch: '$branch'."
}

$repoRoot = [System.IO.Path]::GetFullPath((& git rev-parse --show-toplevel).Trim())
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve the repository root.'
}
$repoRootPrefix = $repoRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar

$alreadyStaged = @(& git diff --cached --name-only)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect staged changes.'
}
if ($alreadyStaged.Count -gt 0) {
    throw "Refusing to continue because changes are already staged: $($alreadyStaged -join ', ')"
}

$resolvedPaths = foreach ($path in $Paths) {
    $candidate = Join-Path $repoRoot $path
    $resolved = [System.IO.Path]::GetFullPath($candidate)
    if (-not $resolved.StartsWith($repoRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes repository root: $path"
    }
    if (-not (Test-Path -LiteralPath $resolved)) {
        $tracked = & git ls-files --error-unmatch -- $path 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Path does not exist and is not tracked: $path"
        }
    }
    $path
}

Invoke-Git -Arguments (@('add', '--') + $resolvedPaths)

$staged = @(& git diff --cached --name-only)
if ($LASTEXITCODE -ne 0 -or $staged.Count -eq 0) {
    throw 'No changes were staged for the feature.'
}

$unexpected = @($staged | Where-Object { $_ -notin $resolvedPaths })
if ($unexpected.Count -gt 0) {
    Invoke-Git -Arguments (@('restore', '--staged', '--') + $staged)
    throw "Unexpected paths were staged: $($unexpected -join ', ')"
}

& git diff --cached --check
if ($LASTEXITCODE -ne 0) {
    Invoke-Git -Arguments (@('restore', '--staged', '--') + $staged)
    throw 'git diff --cached --check failed.'
}

Invoke-Git -Arguments @('commit', '-m', $Message)
