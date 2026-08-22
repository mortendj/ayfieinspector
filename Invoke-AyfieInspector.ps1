############################################################
# Name..............: AyfieInspector                        #
# Author............: Morten Johnsen                         #
############################################################

<#
.SYNOPSIS
Reports on Ayfie Index / Saga installation specifics, on top of Winspect's generic host facts.

.DESCRIPTION
AyfieInspector composes Winspect (generic, product-agnostic host facts) with Ayfie-specific
fact-gathering on top - the rule engine, custom refiners, and the Solr source reference count (all
via the Dashboard API), plus the scheduled Saga restart task and outbound firewall openings Saga
itself needs (neither via the API - built-in cmdlets/network checks instead). Winspect is invoked
as-is and its report text is included unmodified; the Ayfie-specific sections reuse Winspect's own
report-formatting functions (section headers, bolding pass) rather than re-implementing them, so
the combined report reads as one consistent document.

Only true customizations (rules with RuleType "custom", refiners not in the built-in default set)
are reported here, not development-inserted or connector-installation rules. This is deliberately
narrower than the raw, unfiltered rule-engine dump tool - that one is a diagnostic
capture-everything tool; this one renders a verdict-style report about what a customer/admin
actually customized.

.PARAMETER winspectPath
Path to Winspect's Invoke-Winspect.ps1. Defaults to a "Winspect" subdirectory nested under this
script's own directory (the packaged/distributed layout - see Build-AyfieInspectorPackage.ps1),
falling back to a sibling "Winspect" directory next to this project (the local development
checkout layout, where Winspect and AyfieInspector are separate sibling repos).

.PARAMETER outputFormat
Sets the output to text, html or markdown style. Text is the default. Passed through to Winspect
as well, so both halves of the report match.

.PARAMETER outputDestination
Determines the destination of the combined report: terminal, file or both. Both is the default.

.PARAMETER dashboardApiRootUrl
Root URL of the Dashboard API that the rule engine, custom refiners, and source reference count are
all queried through. Defaults to "http://localhost/Dashboard/api" - this must run on the
Saga/Ayfie Index host itself, since that endpoint isn't designed for remote access.

.PARAMETER logLevel
Sets the log level to trace, debug, info, warning or error. Off (no logging) is the default. Passed
through to Winspect as well, so one flag controls both halves. Writes two separate log files (one
per script), named after each script the same way Winspect names its own.

.PARAMETER skipFirewallCheck
Skips the outbound connectivity check (~15 URLs Ayfie/Saga itself needs reachable) - useful to
avoid the added time when firewall state is already known or hasn't changed since the last run.

.EXAMPLE
.\Invoke-AyfieInspector.ps1
Produces a combined Winspect + Ayfie custom-rules report, to the terminal and to a file.
#>

[CmdletBinding()]
param(
    [string]$winspectPath = $(
        $nestedWinspectPath = Join-Path $PSScriptRoot "Winspect\Invoke-Winspect.ps1"
        if (Test-Path $nestedWinspectPath) {
            $nestedWinspectPath
        } else {
            Join-Path (Split-Path $PSScriptRoot -Parent) "Winspect\Invoke-Winspect.ps1"
        }
    ),

    [Parameter(Mandatory=$false)]
    [ValidateSet("html", "markdown", "text")]
    [string]$outputFormat = "text",

    [Parameter(Mandatory=$false)]
    [ValidateSet("terminal", "file", "both")]
    [string]$outputDestination = "both",

    [string]$dashboardApiRootUrl = "http://localhost/Dashboard/api",

    [Parameter(Mandatory=$false)]
    [ValidateSet("trace", "debug", "info", "warning", "error", "off")]
    [string]$logLevel = "off",

    [switch]$skipFirewallCheck
)

if (-not (Test-Path $winspectPath)) {
    Write-Error "Winspect not found at '$winspectPath'. Pass -winspectPath explicitly if it lives elsewhere."
    exit 1
}

$SRC_DIR = Join-Path $PSScriptRoot "src"
$WINSPECT_SRC_DIR = Join-Path (Split-Path $winspectPath -Parent) "src"

# Get-LogFilePath (dot-sourced from Winspect's Logging.ps1 below) derives the log filename from
# $SCRIPT_PATH - Winspect sets this itself at its own top level, but this script never did, so
# turning logging on without this would crash the moment something actually tries to log. This
# gives AyfieInspector its own log file, named after this script, separate from Winspect's own.
$SCRIPT_PATH = $PSCommandPath
. (Join-Path $WINSPECT_SRC_DIR "Constants.ps1")
. (Join-Path $WINSPECT_SRC_DIR "Logging.ps1")
. (Join-Path $WINSPECT_SRC_DIR "Utilities.ps1")
. (Join-Path $WINSPECT_SRC_DIR "ReportFormatting.ps1")
. (Join-Path $SRC_DIR "Constants.ps1")
. (Join-Path $SRC_DIR "DashboardApi.ps1")
. (Join-Path $SRC_DIR "RuleEngineInfo.ps1")
. (Join-Path $SRC_DIR "RefinerInfo.ps1")
. (Join-Path $SRC_DIR "ScheduledTaskInfo.ps1")
. (Join-Path $SRC_DIR "FirewallInfo.ps1")

function Get-CustomRulesReportSections($customRules) {
    # Index-side and query-side rules always get their own section, never merged into one list.
    # "index"/"search" are listed first so they always appear even with zero rules on that side;
    # any other TargetRunner value actually seen among the custom rules still gets its own section
    # rather than being dropped.
    $sideNames = @("index", "search")
    foreach ($group in ($customRules | Group-Object -Property TargetRunner)) {
        if ($sideNames -notcontains $group.Name) {
            $sideNames += $group.Name
        }
    }
    $sectionsRaw = ""
    foreach ($side in $sideNames) {
        $sideRules = @($customRules | Where-Object { $_.TargetRunner -eq $side })
        # Computed here, not inside the closure below - GetNewClosure() only snapshots variables,
        # not functions dot-sourced into the script, so a function call placed inside the closure
        # itself fails to resolve at invocation time (confirmed on a real host: "term
        # 'Get-RulesSummary' is not recognized"). The closure only ever touches the resulting
        # plain string, which it can capture correctly.
        $sideRulesSummary = Get-RulesSummary $sideRules
        $sectionTitle = "CUSTOM $($side.ToUpper()) RULES"
        $lineScriptBlocks = @(
            { "Rules$FIELD_LABEL_SEPARATOR" },
            { "$sideRulesSummary" }.GetNewClosure()
        )
        $sectionsRaw += New-SectionOutput $sectionTitle $lineScriptBlocks
    }
    return $sectionsRaw
}

function Get-CustomRefinersReportSection($dashboardApiRootUrl) {
    $customRefiners = @()
    try {
        $customRefiners = Get-CustomRefiners $dashboardApiRootUrl
    } catch {
        Write-Warning "Failed to retrieve refiners from '$dashboardApiRootUrl/refiners': $_"
    }
    # Computed here, not inside the closure below - see the note in Get-CustomRulesReportSections
    # for why a function call must never live inside a GetNewClosure()'d scriptblock.
    $refinersSummary = Get-RefinersSummary $customRefiners
    $lineScriptBlocks = @(
        { "Refiners$FIELD_LABEL_SEPARATOR" },
        { "$refinersSummary" }.GetNewClosure()
    )
    return New-SectionOutput "CUSTOM REFINERS" $lineScriptBlocks
}

function Get-SolrInfoReportSection($dashboardApiRootUrl) {
    $sourceReferenceCount = "Unavailable"
    try {
        $sourceReferenceCount = Get-SourceReferenceCount $dashboardApiRootUrl
    } catch {
        Write-Warning "Failed to retrieve source reference count from '$dashboardApiRootUrl/sourcereference/count': $_"
    }
    # A single plain (unclosed) scriptblock, not GetNewClosure() - this isn't in a loop, so there's
    # no stale-variable risk to guard against, and a plain scriptblock correctly resolves both
    # $FIELD_LABEL_SEPARATOR (an ancestor script-scope variable) and $sourceReferenceCount (local
    # to this still-active function) via normal dynamic scope resolution, matching Winspect's own
    # single-value line convention (e.g. "CPU cores$FIELD_LABEL_SEPARATOR$(...)").
    # GetNewClosure() would have been wrong here for a different reason than the loop case: it only
    # snapshots variables truly local to the enclosing scope, so combined with $FIELD_LABEL_SEPARATOR
    # in the same block it silently resolved that one to empty (confirmed locally: rendered
    # "Source reference countUnavailable" with the separator missing).
    $lineScriptBlocks = @(
        { "Source reference count$FIELD_LABEL_SEPARATOR$sourceReferenceCount" }
    )
    return New-SectionOutput "SOLR INFO" $lineScriptBlocks
}

function Get-ScheduledRestartReportSection() {
    $restartTaskSummary = $null
    try {
        $restartTask = Get-ScheduledRestartTask
        $restartTaskSummary = Get-ScheduledRestartSummary $restartTask
    } catch {
        Write-Warning "Failed to retrieve the scheduled restart task: $_"
        $restartTaskSummary = [PSCustomObject]@{
            TaskName      = $RESTART_TASK_NAME
            ExecutionTime = "Unavailable"
            Command       = "Unavailable"
            User          = "Unavailable"
        }
    }
    # Plain (unclosed) scriptblocks, not GetNewClosure() - none of these are in a loop, so there's
    # no stale-variable risk, and a plain scriptblock resolves the local $restartTaskSummary
    # correctly via normal dynamic scope resolution (see the SOLR INFO note above for why
    # GetNewClosure() would be wrong, not just unnecessary, here).
    $lineScriptBlocks = @(
        { "Task name$FIELD_LABEL_SEPARATOR$($restartTaskSummary.TaskName)" },
        { "Task execution time$FIELD_LABEL_SEPARATOR$($restartTaskSummary.ExecutionTime)" },
        { "Task command$FIELD_LABEL_SEPARATOR$($restartTaskSummary.Command)" },
        { "Task user$FIELD_LABEL_SEPARATOR$($restartTaskSummary.User)" }
    )
    return New-SectionOutput "SCHEDULED RESTART" $lineScriptBlocks
}

function Get-FirewallOpeningsReportSection() {
    $firewallReport = "Skipped due to -skipFirewallCheck"
    if (-not $skipFirewallCheck) {
        $firewallReport = "Unavailable"
        try {
            $firewallReport = Get-FirewallReport $FIREWALL_OPENINGS $FIREWALL_OPENINGS_ALTERNATES
        } catch {
            Write-Warning "Failed to check firewall openings: $_"
        }
    }
    $lineScriptBlocks = @(
        { "$firewallReport" }
    )
    return New-SectionOutput "FIREWALL OPENINGS" $lineScriptBlocks
}

function Start-AyfieInspector() {
    # Mirrors Winspect's own Start-Winspect exactly (Remove-ExistingLogs + start/end INFO banners) -
    # without this, the log only ever contained DEBUG-level function-call entries from the reused
    # logging functions, with nothing marking where a run actually started or ended.
    Remove-ExistingLogs
    Write-InfoLog "################### Starting $AYFIE_INSPECTOR_VERSION_STRING ###################"

    # Get-SectionHeader/Complete-Report (dot-sourced from Winspect) read these two by that exact
    # name as script-scope globals - $script: is required here so the assignment actually lands in
    # the shared scope those functions see, rather than a function-local shadow only this function
    # would see.
    $script:cmdline_param_OUTPUT_FORMAT = $outputFormat
    Initialize-OutputFormatLayout $outputFormat

    Write-Host "Running Winspect ($winspectPath) for generic host facts..."
    $winspectReportLines = & $winspectPath -outputFormat $outputFormat -outputDestination terminal -logLevel $logLevel
    $winspectReportText = $winspectReportLines -join $PHYSICAL_NEWLINE

    if ($logLevel -ne "off") {
        # Winspect's own Get-LogFilePath names its log after Winspect's own script path - now that
        # Winspect is bundled *inside* AyfieInspector's package, that lands its log one directory
        # deeper (AyfieInspector\Winspect\Invoke-Winspect.log) than where AyfieInspector's own log
        # and report end up. Relocated here so both logs are always found in the same place,
        # regardless of internal packaging structure the user shouldn't need to know about.
        $winspectLogPath = $winspectPath.Replace(".ps1", ".log")
        if (Test-Path $winspectLogPath) {
            $targetLogPath = Join-Path (Split-Path $SCRIPT_PATH -Parent) (Split-Path $winspectLogPath -Leaf)
            try {
                Move-Item -Path $winspectLogPath -Destination $targetLogPath -Force
                Write-Host "Relocated Winspect's log -> $targetLogPath"
            } catch {
                Write-Warning "Could not relocate Winspect's log from '$winspectLogPath' to '$targetLogPath': $_"
            }
        }
    }

    Write-Host "Querying rule engine at $dashboardApiRootUrl/rules ..."
    $allRules = @()
    try {
        $allRules = Get-RuleEngineRules $dashboardApiRootUrl
    } catch {
        Write-Warning "Failed to retrieve rules from '$dashboardApiRootUrl/rules': $_"
    }

    # Only true customizations - rules actually entered via the rule editor - belong in this
    # report. Development-inserted and connector-installation rules carry other RuleType values
    # and are deliberately excluded here (unlike the raw, unfiltered one-off dump tool).
    $customRules = @($allRules | Where-Object { $_.RuleType -eq "custom" })
    $newSectionsRaw = Get-CustomRulesReportSections $customRules

    Write-Host "Querying custom refiners at $dashboardApiRootUrl/refiners ..."
    $newSectionsRaw += Get-CustomRefinersReportSection $dashboardApiRootUrl

    Write-Host "Querying source reference count at $dashboardApiRootUrl/sourcereference/count ..."
    $newSectionsRaw += Get-SolrInfoReportSection $dashboardApiRootUrl

    Write-Host "Checking the scheduled restart task ..."
    $newSectionsRaw += Get-ScheduledRestartReportSection

    if ($skipFirewallCheck) {
        Write-Host "Skipping firewall openings check (-skipFirewallCheck)..."
    } else {
        Write-Host "Checking firewall openings (this can take a while)..."
    }
    $newSectionsRaw += Get-FirewallOpeningsReportSection

    # Reuse Winspect's own bolding/finalization pass on the new sections, via "terminal" so it
    # only returns formatted text here rather than writing a stray winspect-report.* file - the
    # actual single combined-report file is written below instead, honoring the real
    # -outputDestination the user asked for.
    $script:cmdline_param_OUTPUT_DESTINATION = "terminal"
    $formattedNewSectionLines = Complete-Report $newSectionsRaw
    $newSectionsText = $formattedNewSectionLines -join $PHYSICAL_NEWLINE

    $fullReport = $winspectReportText + $PHYSICAL_NEWLINE + $newSectionsText

    $extension = $TEXT_EXTENSION
    if ($outputFormat -eq $HTML_STYLE) { $extension = $HTML_EXTENSION }
    elseif ($outputFormat -eq $MARKDOWN_STYLE) { $extension = $MARKDOWN_EXTENSION }

    if ($FILE_OUTPUTS -contains $outputDestination) {
        Set-Content -Path "ayfieinspector-report.$extension" -Value $fullReport
        Write-Host "Wrote combined report -> ayfieinspector-report.$extension"
    }
    if ($TERMINAL_OUTPUTS -contains $outputDestination) {
        Write-Output $fullReport
    }

    Write-InfoLog "################### Tool execution completed ###################"
}

Start-AyfieInspector
