<#
.SYNOPSIS
    Deploys the CCGS Unity 2021 + WeChat Mini Game template into a target project directory.

.DESCRIPTION
    Copies framework files (.claude/, CLAUDE.md), the Unity 2021.3 skeleton,
    the 6 WeChat ADRs, and the Unity engine reference into a target path,
    then performs a path-rewrite pass that maps engine-agnostic root paths
    (design/, src/, etc.) into the deployed layout (CCGS/Design/,
    Unity/Assets/Scripts/, etc.).

    Source framework is engine-agnostic — the rewrites happen on the COPY in
    the target, never on the source repo.

.PARAMETER TargetPath
    Absolute path where the template should be deployed.

.PARAMETER Mode
    'new'            — fresh project deployment (default).
    'existing-unity' — merge into an existing Unity project (NOT IMPLEMENTED yet).

.PARAMETER ProjectName
    Human-readable project name used in the deployed CLAUDE.md H1.
    Defaults to the leaf directory of TargetPath.

.PARAMETER Force
    Allow deployment into a non-empty target directory. Without this, the
    installer refuses to write into a non-empty directory.

.EXAMPLE
    pwsh .\tools\install-template.ps1 -TargetPath C:\projects\my-wx-game

.EXAMPLE
    pwsh .\tools\install-template.ps1 -TargetPath D:\games\fishing -ProjectName "Fishing Sim" -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [ValidateSet('new', 'existing-unity')]
    [string]$Mode = 'new',

    [string]$ProjectName,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# UTF-8 no BOM encoding for all file writes.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Step {
    param([int]$Number, [string]$Message)
    Write-Host "[$Number] $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

function Fail {
    param([int]$Step, [string]$Path, [string]$Reason)
    Write-Host ""
    Write-Host "ERROR at step $Step" -ForegroundColor Red
    Write-Host "  Path:   $Path" -ForegroundColor Red
    Write-Host "  Reason: $Reason" -ForegroundColor Red
    exit 1
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

function Read-Utf8 {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path)
}


# Step 1 — Validate arguments

Write-Step 1 "Validating arguments"

if ($Mode -eq 'existing-unity') {
    Write-Host "NOT IMPLEMENTED: -Mode existing-unity will be added in a future release." -ForegroundColor Yellow
    Write-Host "For now, use the default -Mode new on a fresh directory." -ForegroundColor Yellow
    exit 2
}

try {
    if (-not (Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
        Write-Info "Created target directory: $TargetPath"
    }
    $TargetPath = (Resolve-Path $TargetPath).Path
} catch {
    Fail 1 $TargetPath "Failed to resolve or create target directory: $($_.Exception.Message)"
}

# Empty-target check
$existingContents = Get-ChildItem -Path $TargetPath -Force -ErrorAction SilentlyContinue
if ($existingContents -and -not $Force) {
    Fail 1 $TargetPath "Target directory is not empty. Pass -Force to overwrite, or choose an empty directory."
}

if (-not $ProjectName) {
    $ProjectName = Split-Path -Leaf $TargetPath
}
Write-Info "TargetPath:  $TargetPath"
Write-Info "ProjectName: $ProjectName"
Write-Info "Force:       $Force"


# Step 2 — Resolve source repo and validate

Write-Step 2 "Resolving source repository"

$SourceRoot = Split-Path -Parent $PSScriptRoot
$requiredSourcePaths = @(
    '.claude',
    'CLAUDE.md',
    'Unity',
    'docs\architecture',
    'docs\engine-reference\unity',
    'README-branch.md'
)
foreach ($rel in $requiredSourcePaths) {
    $full = Join-Path $SourceRoot $rel
    if (-not (Test-Path $full)) {
        Fail 2 $full "Required source path missing. Are you running from a checkout of unity-2021-instant-game branch?"
    }
}
Write-Info "Source root: $SourceRoot"


# Step 3 — Copy .claude/ recursively

Write-Step 3 "Copying .claude/ -> $TargetPath\.claude\"
try {
    Copy-Item -Path (Join-Path $SourceRoot '.claude') -Destination $TargetPath -Recurse -Force
} catch {
    Fail 3 "$SourceRoot\.claude" "Copy failed: $($_.Exception.Message)"
}


# Step 4 — Copy CLAUDE.md

Write-Step 4 "Copying CLAUDE.md"
try {
    Copy-Item -Path (Join-Path $SourceRoot 'CLAUDE.md') -Destination (Join-Path $TargetPath 'CLAUDE.md') -Force
} catch {
    Fail 4 "$SourceRoot\CLAUDE.md" "Copy failed: $($_.Exception.Message)"
}


# Step 5 — Copy Unity/ recursively

Write-Step 5 "Copying Unity/ -> $TargetPath\Unity\"
try {
    Copy-Item -Path (Join-Path $SourceRoot 'Unity') -Destination $TargetPath -Recurse -Force
} catch {
    Fail 5 "$SourceRoot\Unity" "Copy failed: $($_.Exception.Message)"
}


# Step 6 — Copy docs/architecture/ -> CCGS/Docs/architecture/

Write-Step 6 "Copying docs/architecture/ -> $TargetPath\CCGS\Docs\architecture\"
$targetArchDir = Join-Path $TargetPath 'CCGS\Docs\architecture'
try {
    New-Item -ItemType Directory -Path $targetArchDir -Force | Out-Null
    Copy-Item -Path (Join-Path $SourceRoot 'docs\architecture\*') -Destination $targetArchDir -Recurse -Force
} catch {
    Fail 6 $targetArchDir "Copy failed: $($_.Exception.Message)"
}


# Step 7 — Copy docs/engine-reference/unity/ -> CCGS/Docs/engine-reference/unity/

Write-Step 7 "Copying docs/engine-reference/unity/ -> $TargetPath\CCGS\Docs\engine-reference\unity\"
$targetEngineDir = Join-Path $TargetPath 'CCGS\Docs\engine-reference\unity'
try {
    New-Item -ItemType Directory -Path $targetEngineDir -Force | Out-Null
    Copy-Item -Path (Join-Path $SourceRoot 'docs\engine-reference\unity\*') -Destination $targetEngineDir -Recurse -Force
} catch {
    Fail 7 $targetEngineDir "Copy failed: $($_.Exception.Message)"
}


# Step 8 — Copy README-branch.md -> CCGS/Docs/README-branch.md

Write-Step 8 "Copying README-branch.md -> $TargetPath\CCGS\Docs\README-branch.md"
try {
    Copy-Item -Path (Join-Path $SourceRoot 'README-branch.md') -Destination (Join-Path $TargetPath 'CCGS\Docs\README-branch.md') -Force
} catch {
    Fail 8 "$SourceRoot\README-branch.md" "Copy failed: $($_.Exception.Message)"
}


# Step 9 — Create CCGS skeleton (.gitkeep directories)

Write-Step 9 "Creating CCGS/ skeleton"

$ccgsSkeleton = @(
    'CCGS\Design\gdd',
    'CCGS\Design\narrative',
    'CCGS\Design\levels',
    'CCGS\Design\balance',
    'CCGS\Design\registry',
    'CCGS\Design\concepts',
    'CCGS\Docs\api',
    'CCGS\Docs\postmortems',
    'CCGS\Production\session-state',
    'CCGS\Production\session-logs',
    'CCGS\Production\sprints',
    'CCGS\Production\milestones',
    'CCGS\Production\releases',
    'CCGS\Production\epics',
    'CCGS\Production\qa\evidence',
    'CCGS\Production\qa\bugs',
    'CCGS\Tests\unit',
    'CCGS\Tests\integration',
    'CCGS\Tests\performance',
    'CCGS\Tests\playtest',
    'CCGS\Tools\ci',
    'CCGS\Tools\build',
    'CCGS\Tools\asset-pipeline',
    'CCGS\Prototypes'
)

foreach ($rel in $ccgsSkeleton) {
    $dir = Join-Path $TargetPath $rel
    try {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $keep = Join-Path $dir '.gitkeep'
        Write-Utf8NoBom -Path $keep -Content ''
    } catch {
        Fail 9 $dir "Skeleton creation failed: $($_.Exception.Message)"
    }
}
Write-Info "Created $($ccgsSkeleton.Count) directories with .gitkeep markers"


# Step 10 — Path-rewrite pass on .claude/ and CLAUDE.md

Write-Step 10 "Rewriting framework path references"

# Ordered: most-specific first so catch-alls don't pre-empt narrower matches.
$projectContentRewrites = @(
    @{ Pattern = '\bdesign/gdd/';                  Replacement = 'CCGS/Design/gdd/' }
    @{ Pattern = '\bdesign/narrative/';            Replacement = 'CCGS/Design/narrative/' }
    @{ Pattern = '\bdesign/levels/';               Replacement = 'CCGS/Design/levels/' }
    @{ Pattern = '\bdesign/balance/';              Replacement = 'CCGS/Design/balance/' }
    @{ Pattern = '\bdesign/registry/';             Replacement = 'CCGS/Design/registry/' }
    @{ Pattern = '\bdesign/concepts/';             Replacement = 'CCGS/Design/concepts/' }
    @{ Pattern = '\bdesign/';                      Replacement = 'CCGS/Design/' }
    @{ Pattern = '\bdocs/architecture/';           Replacement = 'CCGS/Docs/architecture/' }
    @{ Pattern = '\bdocs/engine-reference/';       Replacement = 'CCGS/Docs/engine-reference/' }
    @{ Pattern = '\bdocs/api/';                    Replacement = 'CCGS/Docs/api/' }
    @{ Pattern = '\bdocs/postmortems/';            Replacement = 'CCGS/Docs/postmortems/' }
    @{ Pattern = '\bproduction/';                  Replacement = 'CCGS/Production/' }
    @{ Pattern = '\btests/unit/';                  Replacement = 'CCGS/Tests/unit/' }
    @{ Pattern = '\btests/integration/';           Replacement = 'CCGS/Tests/integration/' }
    @{ Pattern = '\btests/performance/';           Replacement = 'CCGS/Tests/performance/' }
    @{ Pattern = '\btests/playtest/';              Replacement = 'CCGS/Tests/playtest/' }
    @{ Pattern = '\btests/';                       Replacement = 'CCGS/Tests/' }
    @{ Pattern = '\btools/ci/';                    Replacement = 'CCGS/Tools/ci/' }
    @{ Pattern = '\btools/build/';                 Replacement = 'CCGS/Tools/build/' }
    @{ Pattern = '\btools/asset-pipeline/';        Replacement = 'CCGS/Tools/asset-pipeline/' }
    @{ Pattern = '\btools/';                       Replacement = 'CCGS/Tools/' }
    @{ Pattern = '\bprototypes/';                  Replacement = 'CCGS/Prototypes/' }
)

$sourceCodeRewrites = @(
    @{ Pattern = '\bsrc/core/';        Replacement = 'Unity/Assets/Scripts/Core/' }
    @{ Pattern = '\bsrc/gameplay/';    Replacement = 'Unity/Assets/Scripts/Gameplay/' }
    @{ Pattern = '\bsrc/ai/';          Replacement = 'Unity/Assets/Scripts/AI/' }
    @{ Pattern = '\bsrc/ui/';          Replacement = 'Unity/Assets/Scripts/UI/' }
    @{ Pattern = '\bsrc/networking/';  Replacement = 'Unity/Assets/Scripts/Networking/' }
    @{ Pattern = '\bsrc/tools/';       Replacement = 'Unity/Assets/Scripts/Tools/' }
    @{ Pattern = '\bsrc/';             Replacement = 'Unity/Assets/Scripts/' }
    @{ Pattern = '\bassets/art/';      Replacement = 'Unity/Assets/Art/' }
    @{ Pattern = '\bassets/audio/';    Replacement = 'Unity/Assets/Audio/' }
    @{ Pattern = '\bassets/data/';     Replacement = 'Unity/Assets/Data/' }
    @{ Pattern = '\bassets/shaders/';  Replacement = 'Unity/Assets/Shaders/' }
    @{ Pattern = '\bassets/vfx/';      Replacement = 'Unity/Assets/VFX/' }
    @{ Pattern = '\bassets/';          Replacement = 'Unity/Assets/' }
)

$allRewrites = ($projectContentRewrites + $sourceCodeRewrites) | ForEach-Object {
    [PSCustomObject]@{ Regex = [regex]::new($_.Pattern); Replacement = $_.Replacement }
}

# Files to rewrite: .claude/** of given extensions + CLAUDE.md.
$rewriteExtensions = @('.md', '.sh', '.yaml', '.yml', '.json')
$claudeDir = Join-Path $TargetPath '.claude'
$candidateFiles = @()
$candidateFiles += Get-ChildItem -Path $claudeDir -Recurse -File | Where-Object {
    $rewriteExtensions -contains $_.Extension.ToLower()
}
$candidateFiles += Get-Item (Join-Path $TargetPath 'CLAUDE.md')

$sentinel = '__CLAUDE_DOCS__'
$rewrittenCount = 0
$touchedCount = 0

foreach ($file in $candidateFiles) {
    try {
        $original = Read-Utf8 -Path $file.FullName
        $content = $original

        # Pre-pass safety substitution for files under .claude/docs/.
        $claudeDocsDir = (Join-Path $claudeDir 'docs') + '\'
        $isInClaudeDocs = $file.FullName.StartsWith($claudeDocsDir, [System.StringComparison]::OrdinalIgnoreCase)
        if ($isInClaudeDocs) {
            $content = $content.Replace('.claude/docs/', $sentinel)
        }

        # Apply rewrites in order.
        foreach ($r in $allRewrites) {
            $content = $r.Regex.Replace($content, $r.Replacement)
        }

        # Restore sentinel.
        if ($isInClaudeDocs) {
            $content = $content.Replace($sentinel, '.claude/docs/')
        }

        if ($content -ne $original) {
            Write-Utf8NoBom -Path $file.FullName -Content $content
            $rewrittenCount++
        }
        $touchedCount++
    } catch {
        Fail 10 $file.FullName "Rewrite failed: $($_.Exception.Message)"
    }
}
Write-Info "Inspected $touchedCount files; rewrote $rewrittenCount"


# Step 11 — Customize CLAUDE.md H1

Write-Step 11 "Customizing CLAUDE.md H1 for '$ProjectName'"

$claudePath = Join-Path $TargetPath 'CLAUDE.md'
try {
    $content = Read-Utf8 -Path $claudePath
    $newH1 = "# $ProjectName -- Game Studio (CCGS template: Unity 2021 + WeChat Mini Game)"
    # Replace the entire first heading line.
    $content = $content -replace '(?m)^#\s+Claude Code Game Studios.*$', $newH1
    Write-Utf8NoBom -Path $claudePath -Content $content
} catch {
    Fail 11 $claudePath "Customization failed: $($_.Exception.Message)"
}


# Step 12 — Print Next Steps

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Deployment complete: $ProjectName" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host ""
Write-Host "  1. Open Unity Hub and add the project at:" -ForegroundColor White
Write-Host "       $TargetPath\Unity\" -ForegroundColor Gray
Write-Host "     Unity Hub will detect Unity 2021.3.40f1 from ProjectVersion.txt." -ForegroundColor Gray
Write-Host ""
Write-Host "  2. After Unity finishes the first import, open Edit -> Project Settings" -ForegroundColor White
Write-Host "     and apply the checklist in:" -ForegroundColor White
Write-Host "       $TargetPath\Unity\ProjectSettings\README.md" -ForegroundColor Gray
Write-Host "     (Scripting Backend=IL2CPP, Stripping=High, .NET Standard 2.1," -ForegroundColor Gray
Write-Host "      WebGL Memory=256MB, Color Space=Linear, Brotli, Built-in RP)" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Install the Tuanjie WeChat Mini Game SDK via UPM:" -ForegroundColor White
Write-Host "       Add `"com.qq.weixin.minigame`": `"<git-url>`" to Unity\Packages\manifest.json" -ForegroundColor Gray
Write-Host "       per the SDK README:" -ForegroundColor Gray
Write-Host "       https://github.com/wechat-miniprogram/minigame-tuanjie-transform-sdk" -ForegroundColor Gray
Write-Host "     The SDK installs into Library\PackageCache\com.qq.weixin.minigame@*\" -ForegroundColor Gray
Write-Host "     (NOT into Unity\Assets\Plugins\WeChat\ — that directory stays mostly" -ForegroundColor Gray
Write-Host "      empty under the Facade design; see Plugins\WeChat\README.md)." -ForegroundColor Gray
Write-Host "     IMPORTANT: Verify Tuanjie SDK <-> Unity 2021.3 compatibility before" -ForegroundColor Yellow
Write-Host "     your first WebGL build (see ADR-0001). The SDK targets Tuanjie" -ForegroundColor Yellow
Write-Host "     engine (Unity China fork, Unity 2022 base). If it refuses to load," -ForegroundColor Yellow
Write-Host "     either switch to Tuanjie or pin to an older WX-SDK that supports" -ForegroundColor Yellow
Write-Host "     pure Unity 2021." -ForegroundColor Yellow
Write-Host ""
Write-Host "  4. Review the 6 ADRs (all Status=Proposed):" -ForegroundColor White
Write-Host "       $TargetPath\CCGS\Docs\architecture\" -ForegroundColor Gray
Write-Host "     Update Status to Accepted when you sign off." -ForegroundColor Gray
Write-Host ""
Write-Host "  5. Launch Claude Code from the project root:" -ForegroundColor White
Write-Host "       cd `"$TargetPath`"" -ForegroundColor Gray
Write-Host "       claude" -ForegroundColor Gray
Write-Host ""
Write-Host "  6. (Optional) git init + initial commit." -ForegroundColor White
Write-Host ""
exit 0
