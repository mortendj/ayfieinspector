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

function Get-SolrInfoReportSection($dashboardApiRootUrl, $installDirPath) {
    $sourceReferenceCount = "Unavailable"
    try {
        $sourceReferenceCount = Get-SourceReferenceCount $dashboardApiRootUrl
    } catch {
        Write-Warning "Failed to retrieve source reference count from '$dashboardApiRootUrl/sourcereference/count': $_"
    }
    $solrIndexLanguages = "Unavailable"
    $solrJavaMemory = "Unavailable"
    $solrJavaStackSize = "Unavailable"
    $solrIndexSize = "Unavailable"
    if ($installDirPath -ne "") {
        try {
            $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
            $solrIndexLanguages = Get-DotEnvValue $dotEnvFilePath $SOLR_INDEX_LANGUAGES_KEY
            $solrJavaMemory = Get-DotEnvValue $dotEnvFilePath $SOLR_JAVA_MEM_KEY
            $solrJavaStackSize = Get-DotEnvValue $dotEnvFilePath $SOLR_JAVA_STACK_SIZE_KEY
        } catch {
            Write-Warning "Failed to read Solr .env settings: $_"
        }
        try {
            $solrIndexSize = Get-FormattedDirectorySize (Join-Path $installDirPath $SOLR_INDEX_RELATIVE_PATH)
        } catch {
            Write-Warning "Failed to determine the Solr index size: $_"
        }
    }
    # Plain (unclosed) scriptblocks, not GetNewClosure() - this isn't in a loop, so there's no
    # stale-variable risk to guard against, and a plain scriptblock correctly resolves both
    # $FIELD_LABEL_SEPARATOR (an ancestor script-scope variable) and each local variable via normal
    # dynamic scope resolution, matching Winspect's own single-value line convention (e.g. "CPU
    # cores$FIELD_LABEL_SEPARATOR$(...)"). GetNewClosure() would have been wrong here for a
    # different reason than the loop case: it only snapshots variables truly local to the enclosing
    # scope, so combined with $FIELD_LABEL_SEPARATOR in the same block it silently resolved that one
    # to empty (confirmed locally: rendered "Source reference countUnavailable" with the separator
    # missing).
    $lineScriptBlocks = @(
        { "Solr index languages$FIELD_LABEL_SEPARATOR$solrIndexLanguages" },
        { "Solr java memory$FIELD_LABEL_SEPARATOR$solrJavaMemory" },
        { "Solr java stack size$FIELD_LABEL_SEPARATOR$solrJavaStackSize" },
        { "Solr index size$FIELD_LABEL_SEPARATOR$solrIndexSize" },
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

function Get-SagaInfoReportSection($installDirPath, $gatewayHostname, $connectorApiRootUrl) {
    # Reuses installDirPath/gatewayHostname already resolved once for the gateway certificate
    # check (see Get-SagaGatewayCertificateInfo) rather than re-discovering them here - both are
    # simply "Unavailable" when that resolution failed or was skipped (the pre-installation
    # override case), matching every other section's degrade pattern.
    $installDirDisplay = "Unavailable"
    $sagaVersion = "Unavailable"
    $branding = "Unavailable"
    $gatewayHostnameDisplay = "Unavailable"
    $osSupportSummary = "Unavailable"
    $installedConnectorsFromPlugins = "Unavailable"
    $installedConnectorsFromApi = "Unavailable"
    $connectorsInUse = "Unavailable"
    $runningConnectorContainers = "Unavailable"

    if ($installDirPath -ne "") {
        $installDirDisplay = $installDirPath
        try {
            $sagaVersion = Get-SagaVersion $installDirPath
        } catch {
            Write-Warning "Failed to determine the Saga version: $_"
        }
        try {
            $dotEnvFilePath = Join-Path $installDirPath $DOT_ENV_RELATIVE_PATH
            $branding = Get-DotEnvValue $dotEnvFilePath $BRANDING_KEY
        } catch {
            Write-Warning "Failed to determine the Saga branding: $_"
        }
        try {
            $installedConnectorsFromPlugins = (Get-InstalledConnectorNamesFromPluginsDirectory $installDirPath) -join " "
        } catch {
            Write-Warning "Failed to list installed connectors from the plugins directory: $_"
        }
    }
    if ($gatewayHostname -ne "") {
        $gatewayHostnameDisplay = $gatewayHostname
    }
    try {
        $osSupportSummary = Get-OsSupportSummary (Get-OperatingSystemVersion)
    } catch {
        Write-Warning "Failed to determine OS support status: $_"
    }
    try {
        $apiConnectorNames = Get-InstalledConnectorNames $connectorApiRootUrl
        $installedConnectorsFromApi = $apiConnectorNames -join " "
        $connectorsInUse = (Get-ConnectorNamesInUse $connectorApiRootUrl $apiConnectorNames) -join " "
    } catch {
        Write-Warning "Failed to list installed connectors from '$connectorApiRootUrl': $_"
    }
    try {
        $runningConnectorContainers = Get-RunningConnectorNames
    } catch {
        Write-Warning "Failed to list running connector containers: $_"
    }

    # Plain (unclosed) scriptblocks - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Install directory$FIELD_LABEL_SEPARATOR$installDirDisplay" },
        { "Saga version$FIELD_LABEL_SEPARATOR$sagaVersion" },
        { "Branding$FIELD_LABEL_SEPARATOR$branding" },
        { "Gateway hostname$FIELD_LABEL_SEPARATOR$gatewayHostnameDisplay" },
        { "OS supported by Saga$FIELD_LABEL_SEPARATOR$osSupportSummary" },
        { "Installed connectors (Management Console)$FIELD_LABEL_SEPARATOR$installedConnectorsFromApi" },
        { "Installed connectors (plugins directory)$FIELD_LABEL_SEPARATOR$installedConnectorsFromPlugins" },
        { "Connectors in actual use$FIELD_LABEL_SEPARATOR$connectorsInUse" },
        { "Running connector containers$FIELD_LABEL_SEPARATOR" },
        { "$runningConnectorContainers" }
    )
    return New-SectionOutput "SAGA INFO" $lineScriptBlocks
}

function Get-SagaLicenseInfoReportSection($licenseSummary) {
    # Takes the already-resolved summary rather than resolving it itself - Get-LicensingContainerIp
    # (a docker call) + Get-SagaLicenseSummary (a network call) are both resolved once, early in
    # Start-AyfieInspector, since Add-CustomerNameToReportInfo and
    # Get-ExpirationsAndCapacityDepletionsReportSection both need the same data too; resolving here
    # as well would mean fetching it twice per run for no benefit.
    $customerId = "Unavailable"
    $activationDates = "Unavailable"
    $expirationDates = "Unavailable"
    $userCapacity = "Unavailable"
    $documentCapacity = "Unavailable"
    $features = "Unavailable"
    if ($null -ne $licenseSummary) {
        if ($null -ne $licenseSummary.CustomerId) { $customerId = $licenseSummary.CustomerId }
        if ($null -ne $licenseSummary.ActivationDates) { $activationDates = $licenseSummary.ActivationDates }
        if ($null -ne $licenseSummary.ExpirationDates) { $expirationDates = $licenseSummary.ExpirationDates }
        if ($null -ne $licenseSummary.UserCapacity) { $userCapacity = $licenseSummary.UserCapacity }
        if ($null -ne $licenseSummary.DocumentCapacity) { $documentCapacity = $licenseSummary.DocumentCapacity }
        if ($null -ne $licenseSummary.Features) { $features = $licenseSummary.Features }
    }
    # Plain (unclosed) scriptblocks - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Customer Id$FIELD_LABEL_SEPARATOR$customerId" },
        { "Activation date (utc)$FIELD_LABEL_SEPARATOR$activationDates" },
        { "Expiration date (utc)$FIELD_LABEL_SEPARATOR$expirationDates" },
        { "User capacity$FIELD_LABEL_SEPARATOR$userCapacity" },
        { "Document capacity$FIELD_LABEL_SEPARATOR$documentCapacity" },
        { "Licensed features$FIELD_LABEL_SEPARATOR" },
        { "$features" }
    )
    return New-SectionOutput "SAGA LICENSE INFO" $lineScriptBlocks
}

function Get-ExpirationsAndCapacityDepletionsReportSection($licenseSummary) {
    # Deliberately just the Saga license half of what the older tool this is ported from covers
    # under this same heading - the SSL certificate half is left out here, since AyfieInspector's
    # SAGA CERTIFICATE section already shows its own days-remaining figure
    # ("expires 2026-11-15 (78 days)"), and computing it again here would mean either re-resolving
    # the certificate a second time or fragile-parsing it back out of already-rendered text.
    $daysUntilSagaLicenseExpires = "Unavailable"
    try {
        $daysUntilSagaLicenseExpires = Get-DaysUntilSagaLicenseExpires $licenseSummary
    } catch {
        Write-Warning "Failed to determine days until Saga license expiration: $_"
    }
    # Plain (unclosed) scriptblock - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Days left of Saga license$FIELD_LABEL_SEPARATOR$daysUntilSagaLicenseExpires" }
    )
    return New-SectionOutput "EXPIRATIONS AND CAPACITY DEPLETIONS" $lineScriptBlocks
}

function Add-CustomerNameToReportInfo($winspectReportText, $customerName) {
    Write-FunctionCallLog $PSBoundParameters
    # Spliced in as plain text surgery on Winspect's already-rendered output, exactly like
    # Add-AyfieInspectorVersionToReportInfo above - Winspect has no concept of "customer", so this
    # stays entirely on the AyfieInspector side rather than teaching Winspect anything product-
    # specific. Unlike the version-line splice (which inserts after a specific existing line),
    # Customer is inserted as the very first line of the section, directly after its header -
    # matching the older tool's own REPORT INFO layout, and simply omitted (not "Unavailable")
    # when no customer name could be resolved, since a report predating any known customer
    # (checking a host before Saga is installed) is a normal, not a failure, state.
    if (-not $customerName) {
        Write-ReturnValue $winspectReportText
        return
    }
    $customerLineRaw = "Customer$FIELD_LABEL_SEPARATOR$customerName"
    $customerLineFormatted = (Complete-Report $customerLineRaw) -join $PHYSICAL_NEWLINE

    # Matched by exact equality against the real rendered header line (not a substring search) -
    # "REPORT INFO" alone is common enough that it could appear elsewhere (confirmed by a real test
    # failure: a line of ordinary prose containing that same phrase was matched instead of the
    # actual header, silently splicing the Customer line into the wrong place). Get-SectionHeader
    # reconstructs exactly what Winspect itself would have rendered, in whichever output style is
    # currently active.
    $reportInfoHeaderLine = Get-SectionHeader "REPORT INFO"
    $lines = @($winspectReportText -split $PHYSICAL_NEWLINE)
    $reportInfoHeaderIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq $reportInfoHeaderLine) {
            $reportInfoHeaderIndex = $i
            break
        }
    }
    if ($reportInfoHeaderIndex -eq -1) {
        Write-WarningLog "Could not find the REPORT INFO section header to splice the Customer line after"
        Write-ReturnValue $winspectReportText
    } else {
        $linesBefore = $lines[0..$reportInfoHeaderIndex]
        $linesAfter = if ($reportInfoHeaderIndex -lt $lines.Count - 1) { $lines[($reportInfoHeaderIndex + 1)..($lines.Count - 1)] } else { @() }
        $newLines = $linesBefore + $customerLineFormatted + $linesAfter
        Write-ReturnValue ($newLines -join $PHYSICAL_NEWLINE)
    }
}

function Get-DataSourceUserSyncingReportSection($installDirPath) {
    $adAndAzureAdSync = "Unavailable"
    if ($installDirPath -ne "") {
        try {
            $adAndAzureAdSync = Get-AdAndAzureAdSync $installDirPath
        } catch {
            Write-Warning "Failed to determine AD/Azure AD syncing status: $_"
        }
    }
    # Plain (unclosed) scriptblock - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "AD and Azure AD syncing$FIELD_LABEL_SEPARATOR$adAndAzureAdSync" }
    )
    return New-SectionOutput "DATA SOURCE USER SYNCING" $lineScriptBlocks
}

function Get-DatabaseInfoReportSection($installDirPath) {
    $databaseInfo = [pscustomobject]@{
        Type = "Unavailable"; Name = "Unavailable"; User = "Unavailable"; Server = "Unavailable"; Port = "Unavailable"
    }
    if ($installDirPath -ne "") {
        try {
            $databaseInfo = Get-DatabaseInfo $installDirPath
        } catch {
            Write-Warning "Failed to determine database info: $_"
        }
    }
    # Plain (unclosed) scriptblocks - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Database type$FIELD_LABEL_SEPARATOR$($databaseInfo.Type)" },
        { "Database name$FIELD_LABEL_SEPARATOR$($databaseInfo.Name)" },
        { "Database user$FIELD_LABEL_SEPARATOR$($databaseInfo.User)" },
        { "Database server$FIELD_LABEL_SEPARATOR$($databaseInfo.Server)" },
        { "Database port$FIELD_LABEL_SEPARATOR$($databaseInfo.Port)" }
    )
    return New-SectionOutput "DATABASE INFO" $lineScriptBlocks
}

function Get-DockerImagesReportSection() {
    $dockerImages = "Unavailable"
    try {
        $dockerImages = Get-DockerImagesOfRunningContainers
    } catch {
        Write-Warning "Failed to list Docker images of running containers: $_"
    }
    # Plain (unclosed) scriptblock - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "$dockerImages" }
    )
    return New-SectionOutput "DOCKER IMAGES CURRENTLY IN USE" $lineScriptBlocks
}

function Get-BackupsReportSection($installDirPath) {
    $backupsSummary = [pscustomobject]@{ Count = "Unavailable"; LatestBackup = $null; TotalSize = $null }
    if ($installDirPath -ne "") {
        try {
            $backupsSummary = Get-BackupsSummary $installDirPath
        } catch {
            Write-Warning "Failed to determine backup info: $_"
        }
    }
    # Plain (unclosed) scriptblocks - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Number of backups$FIELD_LABEL_SEPARATOR$($backupsSummary.Count)" }
    )
    if ($backupsSummary.Count -is [int] -and $backupsSummary.Count -gt 0) {
        $lineScriptBlocks += @(
            { "Latest backup$FIELD_LABEL_SEPARATOR$($backupsSummary.LatestBackup)" },
            { "Total size$FIELD_LABEL_SEPARATOR$($backupsSummary.TotalSize)" }
        )
    }
    return New-SectionOutput "BACKUPS" $lineScriptBlocks
}

function Get-CustomEnvFileReportSection($installDirPath) {
    $customEnvFileContent = "Unavailable"
    if ($installDirPath -ne "") {
        try {
            $customEnvFileContent = Get-CustomEnvFileContent $installDirPath
        } catch {
            Write-Warning "Failed to read the custom.env file content: $_"
        }
    }
    # Plain (unclosed) scriptblock - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "$customEnvFileContent" }
    )
    return New-SectionOutput "CUSTOM.ENV FILE CONTENT" $lineScriptBlocks
}

function Get-DataSourceConnectionsReportSection($connectorApiRootUrl) {
    $dataSourceConnectionsSummary = "Unavailable"
    try {
        $dataSourceConnectionsSummary = Get-DataSourceConnectionsSummary $connectorApiRootUrl
    } catch {
        Write-Warning "Failed to retrieve data source connections from '$connectorApiRootUrl': $_"
    }
    # Plain (unclosed) scriptblock - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "$dataSourceConnectionsSummary" }
    )
    return New-SectionOutput "DATA SOURCE CONNECTIONS" $lineScriptBlocks
}

function Get-AuthenticationMethodReportSection() {
    $authenticationMethodSummary = "Unavailable"
    try {
        $authenticationMethodSummary = Get-AuthenticationMethodSummary
    } catch {
        Write-Warning "Failed to determine the authentication method: $_"
    }
    # Plain (unclosed) scriptblock - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Authentication method$FIELD_LABEL_SEPARATOR$authenticationMethodSummary" }
    )
    return New-SectionOutput "AUTHENTICATION METHOD" $lineScriptBlocks
}

function Add-AyfieInspectorVersionToReportInfo($winspectReportText) {
    Write-FunctionCallLog $PSBoundParameters
    # Winspect's REPORT INFO section only ever prints its own version - the combined report is
    # otherwise silent about which AyfieInspector version actually produced the Ayfie-specific
    # sections below it, making a saved report impossible to attribute to a release. Spliced in
    # here as plain text surgery on Winspect's already-rendered output (rather than teaching
    # Winspect anything about AyfieInspector) to keep Winspect itself completely product-agnostic.
    $versionLineRaw = "AyfieInspector version$FIELD_LABEL_SEPARATOR$AYFIE_INSPECTOR_VERSION ($AYFIE_INSPECTOR_VERSION_TIMESTAMP)"
    $versionLineFormatted = (Complete-Report $versionLineRaw) -join $PHYSICAL_NEWLINE

    $lines = @($winspectReportText -split $PHYSICAL_NEWLINE)
    $winspectVersionLineIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "Winspect version") {
            $winspectVersionLineIndex = $i
            break
        }
    }
    if ($winspectVersionLineIndex -eq -1) {
        # Winspect's own wording changed underneath this - degrade to the unmodified report rather
        # than mis-splicing the version line into the wrong place.
        Write-WarningLog "Could not find Winspect's 'Winspect version' line to splice the AyfieInspector version line after"
        Write-ReturnValue $winspectReportText
    } else {
        $linesBefore = $lines[0..$winspectVersionLineIndex]
        $linesAfter = if ($winspectVersionLineIndex -lt $lines.Count - 1) { $lines[($winspectVersionLineIndex + 1)..($lines.Count - 1)] } else { @() }
        $newLines = $linesBefore + $versionLineFormatted + $linesAfter
        Write-ReturnValue ($newLines -join $PHYSICAL_NEWLINE)
    }
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
    # would see. OUTPUT_DESTINATION is pinned to "terminal" for the whole run (not just the real
    # -outputDestination the user asked for) so every Complete-Report call below - both for the
    # version-line splice and for AyfieInspector's own new sections - returns formatted text rather
    # than writing a stray winspect-report.* file; the actual single combined-report file is written
    # once, at the very end, honoring the real $outputDestination.
    $script:cmdline_param_OUTPUT_FORMAT = $outputFormat
    $script:cmdline_param_OUTPUT_DESTINATION = "terminal"
    Initialize-OutputFormatLayout $outputFormat

    Write-Host "Resolving the Saga gateway certificate info..."
    $resolvedCertificateFilePath = ""
    $resolvedCertificateHostname = ""
    $resolvedInstallDirPath = ""
    try {
        $certificateInfo = Get-SagaGatewayCertificateInfo $certificateFilePath
        $resolvedCertificateFilePath = $certificateInfo.CertificateFilePath
        $resolvedCertificateHostname = $certificateInfo.CertificateHostname
        $resolvedInstallDirPath = $certificateInfo.InstallDirPath
    } catch {
        Write-Warning "Could not resolve the Saga gateway certificate info: $_"
    }

    Write-Host "Resolving the Saga license info..."
    # Resolved once, here, rather than inside Get-SagaLicenseInfoReportSection itself -
    # Add-CustomerNameToReportInfo (right below) and Get-ExpirationsAndCapacityDepletionsReportSection
    # (built later, among the other new sections) both need this same data, and it costs a real
    # docker call plus a network call to fetch, so it's fetched once and passed to all three call
    # sites rather than three times. Left as $null (not a placeholder object) on failure, so
    # downstream consumers can tell "resolution failed entirely" apart from "resolved fine, but
    # there's genuinely nothing to report" (e.g. no valid license at all).
    $resolvedLicenseSummary = $null
    try {
        $licensingContainerIp = Get-LicensingContainerIp
        $resolvedLicenseSummary = Get-SagaLicenseSummary $licensingContainerIp
    } catch {
        Write-Warning "Could not resolve the Saga license info: $_"
    }

    Write-Host "Running Winspect ($winspectPath) for generic host facts..."
    $winspectReportLines = & $winspectPath -outputFormat $outputFormat -outputDestination terminal -logLevel $logLevel -certificateFilePath $resolvedCertificateFilePath -certificateHostname $resolvedCertificateHostname -certificateSectionLabel "SAGA CERTIFICATE" -gmsaAccountName $gmsaAccountName
    $winspectReportText = $winspectReportLines -join $PHYSICAL_NEWLINE
    $winspectReportText = Add-AyfieInspectorVersionToReportInfo $winspectReportText
    $winspectReportText = Add-CustomerNameToReportInfo $winspectReportText $resolvedLicenseSummary.CustomerName

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

    # Section order is deliberately importance-first: short, urgent/actionable facts before large,
    # rarely-searched-for dumps - firewall/schedule/count first, then refiners, then the
    # potentially large rule definitions last.
    $newSectionsRaw = Get-ExpirationsAndCapacityDepletionsReportSection $resolvedLicenseSummary

    if ($skipFirewallCheck) {
        Write-Host "Skipping firewall openings check (-skipFirewallCheck)..."
    } else {
        Write-Host "Checking firewall openings (this can take a while)..."
    }
    $newSectionsRaw += Get-FirewallOpeningsReportSection

    Write-Host "Determining the authentication method..."
    $newSectionsRaw += Get-AuthenticationMethodReportSection

    $newSectionsRaw += Get-DataSourceUserSyncingReportSection $resolvedInstallDirPath

    Write-Host "Querying data source connections at $connectorApiRootUrl for the SAGA INFO connector summary..."
    $newSectionsRaw += Get-SagaInfoReportSection $resolvedInstallDirPath $resolvedCertificateHostname $connectorApiRootUrl

    Write-Host "Checking backups..."
    $newSectionsRaw += Get-BackupsReportSection $resolvedInstallDirPath

    $newSectionsRaw += Get-SagaLicenseInfoReportSection $resolvedLicenseSummary

    Write-Host "Reading custom.env file content..."
    $newSectionsRaw += Get-CustomEnvFileReportSection $resolvedInstallDirPath

    Write-Host "Checking the scheduled restart task ..."
    $newSectionsRaw += Get-ScheduledRestartReportSection

    $newSectionsRaw += Get-DatabaseInfoReportSection $resolvedInstallDirPath

    Write-Host "Querying source reference count at $dashboardApiRootUrl/sourcereference/count ..."
    $newSectionsRaw += Get-SolrInfoReportSection $dashboardApiRootUrl $resolvedInstallDirPath

    Write-Host "Querying custom refiners at $dashboardApiRootUrl/refiners ..."
    $newSectionsRaw += Get-CustomRefinersReportSection $dashboardApiRootUrl

    Write-Host "Listing Docker images of running containers..."
    $newSectionsRaw += Get-DockerImagesReportSection

    Write-Host "Querying data source connections at $connectorApiRootUrl ..."
    $newSectionsRaw += Get-DataSourceConnectionsReportSection $connectorApiRootUrl

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
    $newSectionsRaw += Get-CustomRulesReportSections $customRules

    # Reuse Winspect's own bolding/finalization pass on the new sections (OUTPUT_DESTINATION is
    # already pinned to "terminal" from the top of this function, so this only returns formatted
    # text here rather than writing a stray winspect-report.* file - the actual single
    # combined-report file is written below instead, honoring the real -outputDestination the user
    # asked for).
    $formattedNewSectionLines = Complete-Report $newSectionsRaw
    $newSectionsText = $formattedNewSectionLines -join $PHYSICAL_NEWLINE

    # No extra separator newline here - $winspectReportText already ends with the same trailing
    # blank line every other section boundary gets (from Winspect's own New-SectionOutput), and
    # $newSectionsText's first section starts directly with its own header. Adding one here doubled
    # up the blank line specifically at this one seam (confirmed: RESOURCE USAGE -> FIREWALL
    # OPENINGS showed two blank lines where every other boundary in the report showed one).
    $fullReport = $winspectReportText + $newSectionsText

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
