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

function Get-SslCertificateDetailLines($certificateFilePath) {
    Write-FunctionCallLog $PSBoundParameters
    # Resolves just the fields Winspect's own SAGA SSL CERTIFICATE INFO section can't show, since it
    # never hands the resolved certificate object back to its caller - authority, expiration,
    # subject alternative names, private key status. Deliberately merged into that same section
    # (see Add-SslCertificateDetailToWinspectReport below) rather than kept as AyfieInspector's own
    # separate section: both were about the exact same certificate, and a standalone AyfieInspector
    # section used to duplicate Winspect's own live-vs-file issuer check, reporting it twice.
    # Reads from the certificate FILE specifically (not the live HTTPS endpoint, which Winspect's
    # own summary line already checks and reports on within the same merged section), since the
    # private key only ever exists on disk next to it.
    $certificateFileName = "Unavailable"
    $certificateAuthority = "Unavailable"
    $expirationDate = "Unavailable"
    $subjectAlternativeNames = "Unavailable"
    $privateKeyStatus = "Unavailable"
    if ($certificateFilePath -ne "") {
        $certificateFileName = Split-Path $certificateFilePath -Leaf
        $certificate = $null
        try {
            $certificate = Get-CertificateFromFile $certificateFilePath
        } catch {
            Write-Warning "Failed to read the SSL certificate file '$certificateFilePath': $_"
        }
        if ($null -ne $certificate) {
            try {
                $certificateAuthority = Get-CertificateAuthority $certificate
            } catch {
                Write-Warning "Failed to determine the certificate authority: $_"
            }
            $expirationDate = $certificate.NotAfter.ToString("yyyy-MM-dd")
            try {
                $subjectAlternativeNames = Get-CertificateSubjectAlternativeNames $certificate
            } catch {
                Write-Warning "Failed to determine the certificate's subject alternative names: $_"
            }
        }
        try {
            $privateKeyStatus = Get-CertificateKeyEncryptionStatus $certificateFilePath
        } catch {
            Write-Warning "Failed to determine the private key encryption status: $_"
        }
    }
    Write-ReturnValue @(
        "Certificate file$FIELD_LABEL_SEPARATOR$certificateFileName",
        "Certificate authority$FIELD_LABEL_SEPARATOR$certificateAuthority",
        "Expiration date$FIELD_LABEL_SEPARATOR$expirationDate",
        "Subject alternative names$FIELD_LABEL_SEPARATOR$subjectAlternativeNames",
        "Private key$FIELD_LABEL_SEPARATOR$privateKeyStatus"
    )
}

function Add-SslCertificateDetailToWinspectReport($winspectReportText, $detailLines) {
    Write-FunctionCallLog $PSBoundParameters
    # Appended into Winspect's own SAGA SSL CERTIFICATE INFO section (the -certificateSectionLabel
    # renamed ADDITIONAL CERTIFICATE section, right after its own live-vs-file summary line) -
    # merges what used to be two separate sections about the same certificate into one. Same
    # established text-surgery approach as the other Add-*ToWinspectReport/ToReportInfo functions,
    # but appends within a section instead of inserting a whole new one or a single line: finds the
    # section header, then the first blank line after it (New-SectionOutput always closes every
    # section with exactly one trailing blank line), and inserts these lines immediately before
    # that blank line.
    $detailLinesFormatted = (Complete-Report ($detailLines -join $PHYSICAL_NEWLINE)) -join $PHYSICAL_NEWLINE
    $sectionHeaderLine = Get-SectionHeader "SAGA SSL CERTIFICATE INFO"
    $lines = @($winspectReportText -split $PHYSICAL_NEWLINE)
    $sectionHeaderIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq $sectionHeaderLine) {
            $sectionHeaderIndex = $i
            break
        }
    }
    if ($sectionHeaderIndex -eq -1) {
        Write-WarningLog "Could not find Winspect's SAGA SSL CERTIFICATE INFO section header to append certificate detail to"
        Write-ReturnValue $winspectReportText
    } else {
        $contentEndIndex = $sectionHeaderIndex + 1
        while (($contentEndIndex -lt $lines.Count) -and ($lines[$contentEndIndex].Trim() -ne "")) {
            $contentEndIndex++
        }
        $linesBefore = $lines[0..($contentEndIndex - 1)]
        $linesAfter = if ($contentEndIndex -lt $lines.Count) { $lines[$contentEndIndex..($lines.Count - 1)] } else { @() }
        $newLines = $linesBefore + $detailLinesFormatted + $linesAfter
        Write-ReturnValue ($newLines -join $PHYSICAL_NEWLINE)
    }
}

function Add-GmsaAccountSectionToWinspectReport($winspectReportText, $resolvedGmsaAccountName) {
    Write-FunctionCallLog $PSBoundParameters
    # Winspect's own GMSA ACCOUNT section only renders when it was given a non-empty account name
    # (see its own ReportBuilder.ps1 comment) - deliberate there, since a bare Winspect run has no
    # way to tell "no gMSA configured" apart from "caller just didn't pass one". AyfieInspector's own
    # Get-ResolvedGmsaAccountName now auto-discovers the account name from docker/.env, which makes
    # "genuinely no gMSA configured" a common, ordinary result rather than "caller didn't ask" - and
    # ConfigInspector always shows this section either way ("gMSA account: None"). Morten's call: this
    # stays entirely on the AyfieInspector side, splicing in the section Winspect chose to omit,
    # rather than changing Winspect's own opt-in behavior (which other, non-Saga callers of Winspect
    # may still want). When $resolvedGmsaAccountName is non-empty, Winspect already rendered the full
    # section itself - nothing to do here.
    if ($resolvedGmsaAccountName -ne "") {
        Write-ReturnValue $winspectReportText
        return
    }
    $gmsaLineScriptBlocks = @( { "Account name" + $FIELD_LABEL_SEPARATOR + "None" } )
    $gmsaSectionRaw = New-SectionOutput "GMSA ACCOUNT" $gmsaLineScriptBlocks
    # Same trailing-blank-line trim as Add-ExpirationsSectionToWinspectReport - New-SectionOutput's
    # own closing blank line is already baked into $gmsaSectionRaw, so splitting it back into lines
    # produces more than one trailing empty element; trimmed to exactly one so the splice reproduces
    # a single blank line, not two.
    $gmsaSectionFormatted = (Complete-Report $gmsaSectionRaw) -join $PHYSICAL_NEWLINE
    $gmsaSectionLines = @($gmsaSectionFormatted -split $PHYSICAL_NEWLINE)
    while (($gmsaSectionLines.Count -gt 0) -and ($gmsaSectionLines[-1] -eq "")) {
        $gmsaSectionLines = $gmsaSectionLines[0..($gmsaSectionLines.Count - 2)]
    }
    $gmsaSectionLines += ""

    # Spliced in right where Winspect's own GMSA ACCOUNT section would land if it rendered one - the
    # first blank line after RESOURCE USAGE's content (RESOURCE USAGE is always the section
    # immediately before GMSA ACCOUNT in Winspect's own section order).
    $resourceUsageHeaderLine = Get-SectionHeader "RESOURCE USAGE"
    $lines = @($winspectReportText -split $PHYSICAL_NEWLINE)
    $resourceUsageHeaderIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq $resourceUsageHeaderLine) {
            $resourceUsageHeaderIndex = $i
            break
        }
    }
    if ($resourceUsageHeaderIndex -eq -1) {
        Write-WarningLog "Could not find Winspect's RESOURCE USAGE section header to splice the GMSA ACCOUNT section after"
        Write-ReturnValue $winspectReportText
    } else {
        $contentEndIndex = $resourceUsageHeaderIndex + 1
        while (($contentEndIndex -lt $lines.Count) -and ($lines[$contentEndIndex].Trim() -ne "")) {
            $contentEndIndex++
        }
        $insertIndex = $contentEndIndex + 1
        $linesBefore = $lines[0..$contentEndIndex]
        $linesAfter = if ($insertIndex -lt $lines.Count) { $lines[$insertIndex..($lines.Count - 1)] } else { @() }
        $newLines = $linesBefore + $gmsaSectionLines + $linesAfter
        Write-ReturnValue ($newLines -join $PHYSICAL_NEWLINE)
    }
}

function Get-ExpirationsAndCapacityDepletionsReportSection($licenseSummary, $certificateFilePath) {
    # Both days-left figures resolved fresh here rather than reused from elsewhere. The SSL
    # certificate one only needs a local file read (unlike SAGA CERTIFICATE's live HTTPS check,
    # which really would be worth avoiding a second time) - not a meaningful redundancy, so no
    # need to thread a shared value in from Get-SslCertificateDetailReportSection instead.
    $daysUntilSagaLicenseExpires = "Unavailable"
    try {
        $daysUntilSagaLicenseExpires = Get-DaysUntilSagaLicenseExpires $licenseSummary
    } catch {
        Write-Warning "Failed to determine days until Saga license expiration: $_"
    }
    $daysUntilSslCertificateExpires = "Unavailable"
    if ($certificateFilePath -ne "") {
        try {
            $certificate = Get-CertificateFromFile $certificateFilePath
            $daysUntilSslCertificateExpires = (New-TimeSpan -Start (Get-Date) -End $certificate.NotAfter).Days
        } catch {
            Write-Warning "Failed to determine days until SSL certificate expiration: $_"
        }
    }
    # Plain (unclosed) scriptblocks - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Days left of Saga license$FIELD_LABEL_SEPARATOR$daysUntilSagaLicenseExpires" },
        { "Days left of SSL certificate$FIELD_LABEL_SEPARATOR$daysUntilSslCertificateExpires" }
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

function Add-ExpirationsSectionToWinspectReport($winspectReportText, $expirationsSectionText) {
    Write-FunctionCallLog $PSBoundParameters
    # Spliced in right before Winspect's own CERTIFICATES section - the first section after REPORT
    # INFO - so EXPIRATIONS AND CAPACITY DEPLETIONS lands as the report's 2nd block overall, matching
    # ConfigInspector's own position for it (Morten's call: it belongs there, not appended after all
    # of Winspect's own sections like the rest of AyfieInspector's new sections). Same established
    # text-surgery pattern as Add-CustomerNameToReportInfo/Add-AyfieInspectorVersionToReportInfo
    # above - matched by exact equality against Get-SectionHeader's own reconstruction (not a
    # substring search), for the same "wrong line" reason documented on Add-CustomerNameToReportInfo.
    $expirationsSectionFormatted = (Complete-Report $expirationsSectionText) -join $PHYSICAL_NEWLINE
    # New-SectionOutput's own trailing blank-line separator is already baked into
    # $expirationsSectionFormatted - splitting it back into lines below produces more than one
    # trailing empty array element (a byproduct of splitting a string that already ends with the
    # delimiter), which would double the blank line once spliced in among $winspectReportText's own
    # lines. Trimmed to exactly one so the splice reproduces a single blank line, not two -
    # confirmed by a real test failure this caused (11 double-blank-line instances across the
    # report) before this trim was added.
    $expirationsSectionLines = @($expirationsSectionFormatted -split $PHYSICAL_NEWLINE)
    while (($expirationsSectionLines.Count -gt 0) -and ($expirationsSectionLines[-1] -eq "")) {
        $expirationsSectionLines = $expirationsSectionLines[0..($expirationsSectionLines.Count - 2)]
    }
    $expirationsSectionLines += ""
    $certificatesHeaderLine = Get-SectionHeader "CERTIFICATES"
    $lines = @($winspectReportText -split $PHYSICAL_NEWLINE)
    $certificatesHeaderIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq $certificatesHeaderLine) {
            $certificatesHeaderIndex = $i
            break
        }
    }
    if ($certificatesHeaderIndex -eq -1) {
        Write-WarningLog "Could not find Winspect's CERTIFICATES section header to splice the EXPIRATIONS AND CAPACITY DEPLETIONS section before"
        Write-ReturnValue $winspectReportText
    } else {
        $linesBefore = if ($certificatesHeaderIndex -gt 0) { $lines[0..($certificatesHeaderIndex - 1)] } else { @() }
        $linesAfter = $lines[$certificatesHeaderIndex..($lines.Count - 1)]
        $newLines = $linesBefore + $expirationsSectionLines + $linesAfter
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

function Get-SupervisorInfoReportSection($installDirPath, $licenseSummary) {
    $reportEngineContainerStatus = "Unavailable"
    try {
        $reportEngineContainerStatus = Get-ContainerStatus $REPORT_ENGINE_CONTAINER_NAME
    } catch {
        Write-Warning "Failed to determine the report engine container status: $_"
    }
    $reportEngineLicense = "Unavailable"
    try {
        $reportEngineLicense = Test-HasSagaLicenseCapability $licenseSummary $REPORT_ENGINE_LICENSE
    } catch {
        Write-Warning "Failed to determine the report engine license status: $_"
    }
    $lingoConfiguration = "Unavailable"
    if ($installDirPath -ne "") {
        try {
            $lingoConfiguration = Get-LingoDataTypeAndLanguage $installDirPath
        } catch {
            Write-Warning "Failed to determine the report engine's Lingo configuration: $_"
        }
    }
    # Plain (unclosed) scriptblocks - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Report engine container$FIELD_LABEL_SEPARATOR$reportEngineContainerStatus" },
        { "Report engine license$FIELD_LABEL_SEPARATOR$reportEngineLicense" },
        { "Report engine Lingo configuration$FIELD_LABEL_SEPARATOR$lingoConfiguration" }
    )
    return New-SectionOutput "SUPERVISOR INFO" $lineScriptBlocks
}

function Get-PersonalAssistantReportSection($installDirPath) {
    $personalAssistantInfo = [pscustomobject]@{
        Mode = "Unavailable"; MainModel = $null; MainModelDisplayName = $null
        HighQualityModel = $null; HighQualityModelDisplayName = $null
        HighQualityPlusModel = $null; HighQualityPlusModelDisplayName = $null
    }
    if ($installDirPath -ne "") {
        try {
            $personalAssistantInfo = Get-PersonalAssistantInfo $installDirPath
        } catch {
            Write-Warning "Failed to determine Personal Assistant info: $_"
        }
    }
    # Plain (unclosed) scriptblock - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Operational mode$FIELD_LABEL_SEPARATOR$($personalAssistantInfo.Mode)" }
    )
    # Model deployment fields were stripped out of docker/.env by the Saga 6->7 upgrade script -
    # see the note on $PA_MODEL_FIELDS_DROPPED_FROM_SAGA_MAJOR_VERSION (Constants.ps1) - and matches
    # ConfigInspector's own major-version gate for this section. Defaults to including the fields
    # (major version 0) when the Saga version itself can't be determined, since showing
    # "Unavailable" values is more informative than silently hiding the whole block.
    $sagaMajorVersion = 0
    try {
        $sagaVersion = Get-SagaVersion $installDirPath
        if ($sagaVersion -match "^(\d+)") {
            $sagaMajorVersion = [int]$Matches[1]
        }
    } catch {
        Write-Warning "Failed to determine the Saga version for the Personal Assistant model gate: $_"
    }
    if ($sagaMajorVersion -lt $PA_MODEL_FIELDS_DROPPED_FROM_SAGA_MAJOR_VERSION) {
        $lineScriptBlocks += @(
            { "Main model$FIELD_LABEL_SEPARATOR$($personalAssistantInfo.MainModel)" },
            { "Main model display name$FIELD_LABEL_SEPARATOR$($personalAssistantInfo.MainModelDisplayName)" },
            { "High quality model$FIELD_LABEL_SEPARATOR$($personalAssistantInfo.HighQualityModel)" },
            { "High quality model display name$FIELD_LABEL_SEPARATOR$($personalAssistantInfo.HighQualityModelDisplayName)" },
            { "High quality plus model$FIELD_LABEL_SEPARATOR$($personalAssistantInfo.HighQualityPlusModel)" },
            { "High quality plus model display name$FIELD_LABEL_SEPARATOR$($personalAssistantInfo.HighQualityPlusModelDisplayName)" }
        )
    }
    return New-SectionOutput "PERSONAL ASSISTANT" $lineScriptBlocks
}

function Get-LingoInfoReportSection($installDirPath, $licenseSummary) {
    $lingoInfo = [pscustomobject]@{
        Enabled = "Unavailable"; DataTypeAndLanguage = "Unavailable"; Threads = "Unavailable"
        RecycleMemoryThresholdMb = "Unavailable"; RecycleRuns = "Unavailable"; RecycleTimeSeconds = "Unavailable"
    }
    if ($installDirPath -ne "") {
        try {
            $lingoInfo = Get-LingoInfo $installDirPath
        } catch {
            Write-Warning "Failed to determine Lingo info: $_"
        }
    }
    $lingoContainerStatus = "Unavailable"
    try {
        $lingoContainerStatus = Get-ContainerStatus $LINGO_CONTAINER_NAME
    } catch {
        Write-Warning "Failed to determine the Lingo container status: $_"
    }
    $lingoStandardLicense = "Unavailable"
    $lingoGdprLicense = "Unavailable"
    try {
        $lingoStandardLicense = Test-HasSagaLicenseCapability $licenseSummary $LINGO_STANDARD_LICENSE
        $lingoGdprLicense = Test-HasSagaLicenseCapability $licenseSummary $LINGO_GDPR_LICENSE
    } catch {
        Write-Warning "Failed to determine Lingo license status: $_"
    }
    # Plain (unclosed) scriptblocks - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Lingo enabled$FIELD_LABEL_SEPARATOR$($lingoInfo.Enabled)" },
        { "Lingo container$FIELD_LABEL_SEPARATOR$lingoContainerStatus" },
        { "Lingo standard license$FIELD_LABEL_SEPARATOR$lingoStandardLicense" },
        { "Lingo GDPR license$FIELD_LABEL_SEPARATOR$lingoGdprLicense" },
        { "Lingo language (and data type)$FIELD_LABEL_SEPARATOR$($lingoInfo.DataTypeAndLanguage)" },
        { "Lingo threads (a.k.a pipeline pool size)$FIELD_LABEL_SEPARATOR$($lingoInfo.Threads)" },
        { "Lingo recycle memory threshold$FIELD_LABEL_SEPARATOR$($lingoInfo.RecycleMemoryThresholdMb)" },
        { "Lingo recycle runs$FIELD_LABEL_SEPARATOR$($lingoInfo.RecycleRuns)" },
        { "Lingo recycle time (seconds)$FIELD_LABEL_SEPARATOR$($lingoInfo.RecycleTimeSeconds)" }
    )
    return New-SectionOutput "LINGO INFO" $lineScriptBlocks
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

function Get-TemporaryEnvFileChangesReportSection($installDirPath) {
    $removedVariables = "Unavailable"
    $addedVariables = "Unavailable"
    $modifiedVariables = "Unavailable"
    if ($installDirPath -ne "") {
        try {
            $envConfigDiff = Get-EnvConfigDiff $installDirPath
            $removedVariables = $envConfigDiff.Removed
            $addedVariables = $envConfigDiff.Added
            $modifiedVariables = $envConfigDiff.Modified
        } catch {
            Write-Warning "Failed to determine temporary .env file changes: $_"
        }
    }
    # Plain (unclosed) scriptblocks - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "Removed variables$FIELD_LABEL_SEPARATOR$removedVariables" },
        { "Added variables$FIELD_LABEL_SEPARATOR$addedVariables" },
        { "Modified variables$FIELD_LABEL_SEPARATOR$modifiedVariables" }
    )
    return New-SectionOutput "TEMPORARY .ENV FILE CHANGES" $lineScriptBlocks
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

function Get-DatabaseConnectorConfigurationsReportSection($installDirPath) {
    $connectorDefinitionSummary = "Unavailable"
    if ($installDirPath -ne "") {
        try {
            $connectorDefinitionSummary = Get-ConnectorDefinitionSummary $installDirPath
        } catch {
            Write-Warning "Failed to read database connector configurations: $_"
        }
    }
    # Plain (unclosed) scriptblock - see the SOLR INFO note above for why GetNewClosure() would be
    # wrong, not just unnecessary, here.
    $lineScriptBlocks = @(
        { "$connectorDefinitionSummary" }
    )
    return New-SectionOutput "DATABASE CONNECTOR CONFIGURATIONS" $lineScriptBlocks
}

function Get-AuthenticationMethodReportSection($installDirPath) {
    $authenticationMethodSummary = "Unavailable"
    try {
        $authenticationMethodSummary = Get-AuthenticationMethodSummary $installDirPath
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

    $resolvedGmsaAccountName = Get-ResolvedGmsaAccountName $gmsaAccountName $resolvedInstallDirPath

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
    $winspectReportLines = & $winspectPath -outputFormat $outputFormat -outputDestination terminal -logLevel $logLevel -certificateFilePath $resolvedCertificateFilePath -certificateHostname $resolvedCertificateHostname -certificateSectionLabel "SAGA SSL CERTIFICATE INFO" -gmsaAccountName $resolvedGmsaAccountName -monitoringPeriodMinutes $monitoringPeriodMinutes -monitoringSamplingInSeconds $monitoringSamplingInSeconds
    $winspectReportText = $winspectReportLines -join $PHYSICAL_NEWLINE
    $winspectReportText = Add-AyfieInspectorVersionToReportInfo $winspectReportText
    $winspectReportText = Add-CustomerNameToReportInfo $winspectReportText $resolvedLicenseSummary.CustomerName
    $expirationsSectionRaw = Get-ExpirationsAndCapacityDepletionsReportSection $resolvedLicenseSummary $resolvedCertificateFilePath
    $winspectReportText = Add-ExpirationsSectionToWinspectReport $winspectReportText $expirationsSectionRaw
    $sslCertificateDetailLines = Get-SslCertificateDetailLines $resolvedCertificateFilePath
    $winspectReportText = Add-SslCertificateDetailToWinspectReport $winspectReportText $sslCertificateDetailLines
    $winspectReportText = Add-GmsaAccountSectionToWinspectReport $winspectReportText $resolvedGmsaAccountName

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
    # rarely-searched-for dumps - firewall/schedule/count first, then refiners, then the potentially
    # large rule definitions last. EXPIRATIONS AND CAPACITY DEPLETIONS and the SSL certificate detail
    # fields were already spliced into $winspectReportText above (as the report's 2nd block, and
    # merged into Winspect's own SAGA SSL CERTIFICATE INFO section, respectively) - neither is part
    # of this append-after-Winspect's-own-sections list.
    if ($skipFirewallCheck) {
        Write-Host "Skipping firewall openings check (-skipFirewallCheck)..."
    } else {
        Write-Host "Checking firewall openings (this can take a while)..."
    }
    $newSectionsRaw = Get-FirewallOpeningsReportSection

    Write-Host "Determining the authentication method..."
    $newSectionsRaw += Get-AuthenticationMethodReportSection $resolvedInstallDirPath

    $newSectionsRaw += Get-DataSourceUserSyncingReportSection $resolvedInstallDirPath

    Write-Host "Querying data source connections at $connectorApiRootUrl for the SAGA INFO connector summary..."
    $newSectionsRaw += Get-SagaInfoReportSection $resolvedInstallDirPath $resolvedCertificateHostname $connectorApiRootUrl

    Write-Host "Checking backups..."
    $newSectionsRaw += Get-BackupsReportSection $resolvedInstallDirPath

    $newSectionsRaw += Get-SagaLicenseInfoReportSection $resolvedLicenseSummary

    Write-Host "Reading custom.env file content..."
    $newSectionsRaw += Get-CustomEnvFileReportSection $resolvedInstallDirPath

    Write-Host "Comparing the running docker/.env against the as-shipped reference..."
    $newSectionsRaw += Get-TemporaryEnvFileChangesReportSection $resolvedInstallDirPath

    Write-Host "Checking the scheduled restart task ..."
    $newSectionsRaw += Get-ScheduledRestartReportSection

    $newSectionsRaw += Get-DatabaseInfoReportSection $resolvedInstallDirPath

    $newSectionsRaw += Get-SupervisorInfoReportSection $resolvedInstallDirPath $resolvedLicenseSummary

    $newSectionsRaw += Get-PersonalAssistantReportSection $resolvedInstallDirPath

    $newSectionsRaw += Get-LingoInfoReportSection $resolvedInstallDirPath $resolvedLicenseSummary

    Write-Host "Querying source reference count at $dashboardApiRootUrl/sourcereference/count ..."
    $newSectionsRaw += Get-SolrInfoReportSection $dashboardApiRootUrl $resolvedInstallDirPath

    Write-Host "Querying custom refiners at $dashboardApiRootUrl/refiners ..."
    $newSectionsRaw += Get-CustomRefinersReportSection $dashboardApiRootUrl

    Write-Host "Listing Docker images of running containers..."
    $newSectionsRaw += Get-DockerImagesReportSection

    Write-Host "Querying data source connections at $connectorApiRootUrl ..."
    $newSectionsRaw += Get-DataSourceConnectionsReportSection $connectorApiRootUrl

    $newSectionsRaw += Get-DatabaseConnectorConfigurationsReportSection $resolvedInstallDirPath

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
