BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../../Winspect/src/ReportFormatting.ps1"
    . "$PSScriptRoot/../../Winspect/src/SystemQuery.ps1"
    . "$PSScriptRoot/../../Winspect/src/HostIdentity.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/DashboardApi.ps1"
    . "$PSScriptRoot/../src/RuleEngineInfo.ps1"
    . "$PSScriptRoot/../src/RefinerInfo.ps1"
    . "$PSScriptRoot/../src/ScheduledTaskInfo.ps1"
    . "$PSScriptRoot/../src/FirewallInfo.ps1"
    . "$PSScriptRoot/../src/AuthenticationInfo.ps1"
    . "$PSScriptRoot/../src/SagaCertificateInfo.ps1"
    . "$PSScriptRoot/../src/SagaInfo.ps1"
    . "$PSScriptRoot/../src/EnvFileInfo.ps1"
    . "$PSScriptRoot/../src/ConnectorApi.ps1"
    . "$PSScriptRoot/../src/DataSourceConnectionInfo.ps1"
    . "$PSScriptRoot/../src/MainOrchestration.ps1"

    # New-SectionOutput/Get-SectionHeader/Complete-Report (dot-sourced above) need these set the
    # same way Start-AyfieInspector itself sets them before building any section.
    $cmdline_param_OUTPUT_FORMAT = "text"
    $cmdline_param_OUTPUT_DESTINATION = "terminal"
    Initialize-OutputFormatLayout "text"

    function New-FakeRule($ruleName, $ruleType, $targetRunner) {
        return [pscustomobject]@{
            RuleName = $ruleName; RuleType = $ruleType; Version = "1"; SortOrder = 1
            LastModifiedDate = "2026-01-01T00:00:00Z"; ConnectorTypeId = $null
            TargetRunner = $targetRunner; Definition = "<rules></rules>"
        }
    }
}

Describe "Add-AyfieInspectorVersionToReportInfo" {
    # Regression test: the combined report only ever showed which Winspect version produced it,
    # never which AyfieInspector version - confirmed as a real gap on a production run (KTH,
    # 2026-08-26), since the Ayfie-specific sections below REPORT INFO have no other attribution.

    It "inserts an AyfieInspector version line directly after Winspect's own Winspect version line" {
        $winspectReportText = @(
            "####################### REPORT INFO ########################",
            "Local time: 2026-08-26 17:16:02",
            "User: kth-search-prod\prod-ayfie-admin",
            "Winspect version: 0.10.0 (2026-08-26)",
            "Running elevated: Yes"
        ) -join $PHYSICAL_NEWLINE

        $result = Add-AyfieInspectorVersionToReportInfo $winspectReportText
        $resultLines = @($result -split $PHYSICAL_NEWLINE)

        $winspectVersionIndex = [array]::IndexOf($resultLines, "Winspect version: 0.10.0 (2026-08-26)")
        $winspectVersionIndex | Should -BeGreaterThan -1
        $resultLines[$winspectVersionIndex + 1] | Should -Match "^AyfieInspector version: $([regex]::Escape($AYFIE_INSPECTOR_VERSION))"
        $resultLines[$winspectVersionIndex + 2] | Should -Be "Running elevated: Yes"
    }

    It "returns the original text unchanged if Winspect's Winspect version line can't be found" {
        $winspectReportText = @("Some unrelated report text", "with no version line at all") -join $PHYSICAL_NEWLINE

        Add-AyfieInspectorVersionToReportInfo $winspectReportText | Should -Be $winspectReportText
    }
}

Describe "Get-CustomRulesReportSections" {
    It "always produces both an index and a search section, even with no rules at all" {
        $result = Get-CustomRulesReportSections @()

        $result | Should -Match "CUSTOM INDEX RULES"
        $result | Should -Match "CUSTOM SEARCH RULES"
    }

    It "keeps index-side and search-side rules in separate sections, never merged" {
        $rules = @(
            (New-FakeRule "Index Rule" "custom" "index"),
            (New-FakeRule "Search Rule" "custom" "search")
        )

        $result = Get-CustomRulesReportSections $rules

        $indexSectionStart = $result.IndexOf("CUSTOM INDEX RULES")
        $searchSectionStart = $result.IndexOf("CUSTOM SEARCH RULES")
        $indexRuleAt = $result.IndexOf("Index Rule")
        $searchRuleAt = $result.IndexOf("Search Rule")

        # Index Rule must appear after the INDEX heading but before the SEARCH heading, and
        # vice versa for Search Rule - i.e. each rule stays inside its own section.
        $indexRuleAt | Should -BeGreaterThan $indexSectionStart
        $indexRuleAt | Should -BeLessThan $searchSectionStart
        $searchRuleAt | Should -BeGreaterThan $searchSectionStart
    }

    It "gives an unexpected TargetRunner value its own section rather than dropping it" {
        $rules = @(New-FakeRule "Odd Rule" "custom" "somethingElse")

        $result = Get-CustomRulesReportSections $rules

        $result | Should -Match "CUSTOM SOMETHINGELSE RULES"
        $result | Should -Match "Odd Rule"
    }
}

Describe "Get-CustomRefinersReportSection" {
    It "includes the refiners summary under a CUSTOM REFINERS heading" {
        Mock Get-CustomRefiners { return ,@([pscustomobject]@{
            RefinerName = "Department"; DisplayName = "Department"; FieldName = "via_ssimd_department"
            FacetType = "FacetField"; SelectionLimit = 1000; Enabled = $true; SortOrder = 1
        }) }

        $result = Get-CustomRefinersReportSection "http://localhost/Dashboard/api"

        $result | Should -Match "CUSTOM REFINERS"
        $result | Should -Match "Department"
    }

    It "degrades gracefully (no crash, 'No custom refiners found') when the API call fails" {
        Mock Get-CustomRefiners { throw "connection refused" }

        $result = Get-CustomRefinersReportSection "http://localhost/Dashboard/api"

        $result | Should -Match "No custom refiners found"
    }
}

Describe "Get-SolrInfoReportSection" {
    # Direct regression test for a real bug found on a production host: an earlier version
    # combined the label, separator, and value into a single GetNewClosure()'d scriptblock, which
    # silently dropped $FIELD_LABEL_SEPARATOR (rendering "Source reference countUnavailable" with
    # no separator) because GetNewClosure() only snapshots variables truly local to the enclosing
    # function, not ones inherited from an ancestor scope.

    It "includes the field label separator between the label and the value" {
        Mock Get-SourceReferenceCount { "1,218,445" }

        $result = Get-SolrInfoReportSection "http://localhost/Dashboard/api"

        $result | Should -Match "Source reference count$([regex]::Escape($FIELD_LABEL_SEPARATOR))1,218,445"
    }

    It "reports 'Unavailable' (with the separator still present) when the API call fails" {
        Mock Get-SourceReferenceCount { throw "connection refused" }

        $result = Get-SolrInfoReportSection "http://localhost/Dashboard/api"

        $result | Should -Match "Source reference count$([regex]::Escape($FIELD_LABEL_SEPARATOR))Unavailable"
    }
}

Describe "Get-ScheduledRestartReportSection" {
    It "reports all four fields when a real task is found" {
        Mock Get-ScheduledRestartTask {
            [pscustomobject]@{
                TaskName  = "Restart-Saga"
                Actions   = @([pscustomobject]@{ Arguments = ".\stop-saga.ps1" })
                Triggers  = @([pscustomobject]@{ DaysOfWeek = $null; StartBoundary = "2026-01-01T04:00:00Z"; WeeksInterval = 1 })
                Principal = [pscustomobject]@{ UserId = "ayfie" }
            }
        }

        $result = Get-ScheduledRestartReportSection

        $result | Should -Match "Restart-Saga"
        $result | Should -Match "Daily at 04:00"
        $result | Should -Match "ayfie"
    }

    It "reports 'No scheduled restart' for every field when no task exists" {
        Mock Get-ScheduledRestartTask { $null }

        $result = Get-ScheduledRestartReportSection

        $result | Should -Match "No scheduled restart"
    }

    It "degrades gracefully to 'Unavailable' when the check itself fails" {
        Mock Get-ScheduledRestartTask { throw "access denied" }

        $result = Get-ScheduledRestartReportSection

        $result | Should -Match "Unavailable"
    }
}

Describe "Get-FirewallOpeningsReportSection" {
    It "skips the actual check and says so when -skipFirewallCheck is set" {
        $skipFirewallCheck = $true
        Mock Get-FirewallReport { throw "should not be called" }

        $result = Get-FirewallOpeningsReportSection

        $result | Should -Match "Skipped due to -skipFirewallCheck"
    }

    It "runs the real check and includes its result when not skipped" {
        $skipFirewallCheck = $false
        Mock Get-FirewallReport { "Reachable sites:`n    example.com" }

        $result = Get-FirewallOpeningsReportSection

        $result | Should -Match "example\.com"
    }
}

Describe "Get-AuthenticationMethodReportSection" {
    It "includes the authentication method under an AUTHENTICATION METHOD heading" {
        Mock Get-AuthenticationMethodSummary { "Entra ID" }

        $result = Get-AuthenticationMethodReportSection

        $result | Should -Match "AUTHENTICATION METHOD"
        $result | Should -Match "Entra ID"
    }

    It "degrades gracefully (no crash, 'Unavailable') when the check itself fails" {
        Mock Get-AuthenticationMethodSummary { throw "docker exec failed" }

        $result = Get-AuthenticationMethodReportSection

        $result | Should -Match "Unavailable"
    }
}

Describe "Get-SagaInfoReportSection" {
    BeforeEach {
        Mock Get-OperatingSystemVersion { "Windows Server 2022 Standard (10.0.20348, build 20348)" }
    }

    It "includes the install directory, Saga version, branding, and gateway hostname when all are available" {
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com"

        $result | Should -Match "SAGA INFO"
        $result | Should -Match "Install directory.*C:\\Saga\\"
        $result | Should -Match "Saga version.*7\.19\.0"
        $result | Should -Match "Branding.*custom"
        $result | Should -Match "Gateway hostname.*engine\.example\.com"
    }

    It "reports every field as 'Unavailable' when the install directory couldn't be resolved" {
        # Matches the pre-installation override case (no running install to discover facts from)
        # and the case where Get-SagaGatewayCertificateInfo itself failed entirely.
        Mock Get-SagaVersion { throw "should not be called" }
        Mock Get-DotEnvValue { throw "should not be called" }

        $result = Get-SagaInfoReportSection "" ""

        $result | Should -Match "Install directory.*Unavailable"
        $result | Should -Match "Saga version.*Unavailable"
        $result | Should -Match "Branding.*Unavailable"
        $result | Should -Match "Gateway hostname.*Unavailable"
    }

    It "degrades the version and branding fields independently when the install directory is known but one lookup fails" {
        Mock Get-SagaVersion { throw "git.version not found" }
        Mock Get-DotEnvValue { "ayfie" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com"

        $result | Should -Match "Saga version.*Unavailable"
        $result | Should -Match "Branding.*ayfie"
    }

    It "reports 'Supported' when the detected OS is on Saga's supported list" {
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com"

        $result | Should -Match "OS supported by Saga.*Supported"
    }

    It "reports a warning (not a blocking error) when the detected OS is not on Saga's supported list" {
        Mock Get-OperatingSystemVersion { "Windows Server 2016 Standard (10.0.14393, build 14393)" }
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com"

        $result | Should -Match "OS supported by Saga.*WARNING.*not a version supported by Ayfie Index \(Saga\)"
    }

    It "reports 'Unavailable' for OS support if the OS itself can't be determined" {
        Mock Get-OperatingSystemVersion { throw "WMI unavailable" }
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com"

        $result | Should -Match "OS supported by Saga.*Unavailable"
    }
}

Describe "Get-DataSourceConnectionsReportSection" {
    It "includes the connections summary under a DATA SOURCE CONNECTIONS heading" {
        Mock Get-DataSourceConnectionsSummary { "NetData (fileserver)" }

        $result = Get-DataSourceConnectionsReportSection "http://localhost/api/connector-broker/v1"

        $result | Should -Match "DATA SOURCE CONNECTIONS"
        $result | Should -Match "NetData \(fileserver\)"
    }

    It "degrades gracefully (no crash, 'Unavailable') when the API call fails" {
        Mock Get-DataSourceConnectionsSummary { throw "connection refused" }

        $result = Get-DataSourceConnectionsReportSection "http://localhost/api/connector-broker/v1"

        $result | Should -Match "Unavailable"
    }
}

Describe "Get-CustomEnvFileReportSection" {
    It "includes the redacted custom.env content under a CUSTOM.ENV FILE CONTENT heading" {
        Mock Get-CustomEnvFileContent { "AYFIE_SAGA_BRANDING_KEY=custom" }

        $result = Get-CustomEnvFileReportSection "C:\Saga\"

        $result | Should -Match "CUSTOM\.ENV FILE CONTENT"
        $result | Should -Match "AYFIE_SAGA_BRANDING_KEY=custom"
    }

    It "reports 'Unavailable' when the install directory couldn't be resolved" {
        Mock Get-CustomEnvFileContent { throw "should not be called" }

        $result = Get-CustomEnvFileReportSection ""

        $result | Should -Match "Unavailable"
    }

    It "degrades gracefully to 'Unavailable' when reading the file fails" {
        Mock Get-CustomEnvFileContent { throw "access denied" }

        $result = Get-CustomEnvFileReportSection "C:\Saga\"

        $result | Should -Match "Unavailable"
    }
}
