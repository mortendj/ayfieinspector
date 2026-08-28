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

.PARAMETER connectorApiRootUrl
Root URL of the connector-broker API that the data source connections section is queried through.
Defaults to "http://localhost/api/connector-broker/v1" - like dashboardApiRootUrl, this must run on
the Saga/Ayfie Index host itself.

.PARAMETER gmsaAccountName
Name of a gMSA (group Managed Service Account) to validate, passed straight through to Winspect's
own -gmsaAccountName parameter. Adds a GMSA ACCOUNT section to the report when supplied; omitted
entirely otherwise.

.PARAMETER logLevel
Sets the log level to trace, debug, info, warning or error. Off (no logging) is the default. Passed
through to Winspect as well, so one flag controls both halves. Writes two separate log files (one
per script), named after each script the same way Winspect names its own.

.PARAMETER skipFirewallCheck
Skips the outbound connectivity check (~15 URLs Ayfie/Saga itself needs reachable) - useful to
avoid the added time when firewall state is already known or hasn't changed since the last run.

.PARAMETER certificateFilePath
Path to the Saga gateway certificate file. By default the certificate is checked live over HTTPS
against the configured gateway hostname (auto-discovered from the running licensing container's
install directory and its .env file) - the real proof of what's actually being served - and this
file is only used if that live check fails (e.g. Saga is stopped). Set this explicitly only when
checking a host before Saga is installed there - with no running install yet, there's no live
gateway to reach and no install directory to auto-discover from, so the check becomes file-only.
Passed through to Winspect, giving the combined report a dedicated section for the actual gateway
certificate alongside Winspect's generic certificate-store scan.

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

    [string]$connectorApiRootUrl = "http://localhost/api/connector-broker/v1",

    [Parameter(Mandatory=$false)]
    [ValidateSet("trace", "debug", "info", "warning", "error", "off")]
    [string]$logLevel = "off",

    [switch]$skipFirewallCheck,

    [string]$certificateFilePath = "",

    [string]$gmsaAccountName = ""
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
. (Join-Path $WINSPECT_SRC_DIR "SystemQuery.ps1")
. (Join-Path $WINSPECT_SRC_DIR "HostIdentity.ps1")
. (Join-Path $SRC_DIR "Constants.ps1")
. (Join-Path $SRC_DIR "DashboardApi.ps1")
. (Join-Path $SRC_DIR "RuleEngineInfo.ps1")
. (Join-Path $SRC_DIR "RefinerInfo.ps1")
. (Join-Path $SRC_DIR "ScheduledTaskInfo.ps1")
. (Join-Path $SRC_DIR "FirewallInfo.ps1")
. (Join-Path $SRC_DIR "SagaCertificateInfo.ps1")
. (Join-Path $SRC_DIR "AuthenticationInfo.ps1")
. (Join-Path $SRC_DIR "SagaInfo.ps1")
. (Join-Path $SRC_DIR "EnvFileInfo.ps1")
. (Join-Path $SRC_DIR "EnvConfigDiffInfo.ps1")
. (Join-Path $SRC_DIR "ConnectorApi.ps1")
. (Join-Path $SRC_DIR "DataSourceConnectionInfo.ps1")
. (Join-Path $SRC_DIR "ConnectorDefinitionInfo.ps1")
. (Join-Path $SRC_DIR "DatabaseInfo.ps1")
. (Join-Path $SRC_DIR "DirectorySizeInfo.ps1")
. (Join-Path $SRC_DIR "DockerInfo.ps1")
. (Join-Path $SRC_DIR "BackupInfo.ps1")
. (Join-Path $SRC_DIR "LicenseInfo.ps1")
. (Join-Path $SRC_DIR "LingoInfo.ps1")
. (Join-Path $SRC_DIR "PersonalAssistantInfo.ps1")
. (Join-Path $SRC_DIR "MainOrchestration.ps1")

Start-AyfieInspector
