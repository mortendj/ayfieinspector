BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../../Winspect/src/ReportFormatting.ps1"
    . "$PSScriptRoot/../../Winspect/src/SystemQuery.ps1"
    . "$PSScriptRoot/../../Winspect/src/HostIdentity.ps1"
    . "$PSScriptRoot/../../Winspect/src/Certificates.ps1"
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
    . "$PSScriptRoot/../src/EnvConfigDiffInfo.ps1"
    . "$PSScriptRoot/../src/ConnectorApi.ps1"
    . "$PSScriptRoot/../src/DataSourceConnectionInfo.ps1"
    . "$PSScriptRoot/../src/ConnectorDefinitionInfo.ps1"
    . "$PSScriptRoot/../src/DatabaseInfo.ps1"
    . "$PSScriptRoot/../src/DirectorySizeInfo.ps1"
    . "$PSScriptRoot/../src/DockerInfo.ps1"
    . "$PSScriptRoot/../src/BackupInfo.ps1"
    . "$PSScriptRoot/../src/LicenseInfo.ps1"
    . "$PSScriptRoot/../src/LingoInfo.ps1"
    . "$PSScriptRoot/../src/PersonalAssistantInfo.ps1"
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

Describe "Get-SslCertificateDetailLines" {
    # No longer its own section (no header, no live-vs-file check) - merged into Winspect's own
    # SAGA SSL CERTIFICATE INFO section by Add-SslCertificateDetailToWinspectReport below, since
    # that already has its own live-vs-file issuer check; this only resolves the extra fields it
    # can't expose (it never hands the resolved certificate object back to its caller).
    It "resolves certificate file name, authority, expiration date, subject alternative names, and private key status" {
        Mock Get-CertificateFromFile { [pscustomobject]@{ Issuer = "CN=DigiCert Global CA"; NotAfter = [datetime]"2026-10-24" } }
        Mock Get-CertificateAuthority { "CN=DigiCert Global CA" }
        Mock Get-CertificateSubjectAlternativeNames { "search.example.com, search-alt.example.com" }
        Mock Get-CertificateKeyEncryptionStatus { "Encrypted" }

        $result = Get-SslCertificateDetailLines "C:\Saga\volumes\Traefik\certs\gateway.crt"

        $result | Should -Contain "Certificate file${FIELD_LABEL_SEPARATOR}gateway.crt"
        $result | Should -Contain "Certificate authority${FIELD_LABEL_SEPARATOR}CN=DigiCert Global CA"
        $result | Should -Contain "Expiration date${FIELD_LABEL_SEPARATOR}2026-10-24"
        $result | Should -Contain "Subject alternative names${FIELD_LABEL_SEPARATOR}search.example.com, search-alt.example.com"
        $result | Should -Contain "Private key${FIELD_LABEL_SEPARATOR}Encrypted"
    }

    It "shows only the filename, not the full path, for the certificate file" {
        # Regression test: this used to omit the certificate filename entirely - confirmed missing
        # versus ConfigInspector's own "Certificate file: <name>.crt" line during a real KTH
        # comparison. Matches ConfigInspector's own convention of showing just the filename.
        Mock Get-CertificateFromFile { [pscustomobject]@{ Issuer = "CN=DigiCert Global CA"; NotAfter = [datetime]"2026-10-24" } }
        Mock Get-CertificateAuthority { "CN=DigiCert Global CA" }
        Mock Get-CertificateSubjectAlternativeNames { "search.example.com" }
        Mock Get-CertificateKeyEncryptionStatus { "Encrypted" }

        $result = Get-SslCertificateDetailLines "C:\Saga\volumes\Traefik\certs\kth-search-prod.sys.kth.se.crt"

        $result | Should -Contain "Certificate file${FIELD_LABEL_SEPARATOR}kth-search-prod.sys.kth.se.crt"
    }

    It "reports every field as 'Unavailable' when no certificate file path is known" {
        Mock Get-CertificateFromFile { throw "should not be called" }

        $result = Get-SslCertificateDetailLines ""

        $result | Should -Contain "Certificate file${FIELD_LABEL_SEPARATOR}Unavailable"
        $result | Should -Contain "Certificate authority${FIELD_LABEL_SEPARATOR}Unavailable"
        $result | Should -Contain "Expiration date${FIELD_LABEL_SEPARATOR}Unavailable"
        $result | Should -Contain "Subject alternative names${FIELD_LABEL_SEPARATOR}Unavailable"
        $result | Should -Contain "Private key${FIELD_LABEL_SEPARATOR}Unavailable"
    }

    It "still reports the private key status when the certificate file itself can't be read" {
        Mock Get-CertificateFromFile { throw "file not found" }
        Mock Get-CertificateKeyEncryptionStatus { "Unencrypted" }

        $result = Get-SslCertificateDetailLines "C:\Saga\volumes\Traefik\certs\gateway.crt"

        $result | Should -Contain "Certificate authority${FIELD_LABEL_SEPARATOR}Unavailable"
        $result | Should -Contain "Private key${FIELD_LABEL_SEPARATOR}Unencrypted"
    }

    It "degrades gracefully to 'Unavailable' when the private key file itself can't be read" {
        Mock Get-CertificateFromFile { [pscustomobject]@{ Issuer = "CN=DigiCert Global CA"; NotAfter = [datetime]"2026-10-24" } }
        Mock Get-CertificateAuthority { "CN=DigiCert Global CA" }
        Mock Get-CertificateSubjectAlternativeNames { "search.example.com" }
        Mock Get-CertificateKeyEncryptionStatus { throw "key file not found" }

        $result = Get-SslCertificateDetailLines "C:\Saga\volumes\Traefik\certs\gateway.crt"

        $result | Should -Contain "Certificate authority${FIELD_LABEL_SEPARATOR}CN=DigiCert Global CA"
        $result | Should -Contain "Private key${FIELD_LABEL_SEPARATOR}Unavailable"
    }
}

Describe "Add-SslCertificateDetailToWinspectReport" {
    # SAGA CERTIFICATE and SSL CERTIFICATE INFO used to be two separate sections about the exact
    # same certificate - merged into one ("SAGA SSL CERTIFICATE INFO") on Morten's call, appending
    # AyfieInspector's extra fields directly into Winspect's own section rather than keeping a
    # second header for the same certificate.
    It "appends the detail lines inside the SAGA SSL CERTIFICATE INFO section, before its trailing blank line" {
        $sagaCertHeader = Get-SectionHeader "SAGA SSL CERTIFICATE INFO"
        $winspectReportText = @(
            $sagaCertHeader,
            "kth-search-prod.sys.kth.se -> expires 2026-10-24 (54 days) - checked live via HTTPS (issuer matches the certificate file)",
            "",
            "###################### HOST IDENTITY #######################",
            "Hostname: kth-search-prod"
        ) -join $PHYSICAL_NEWLINE

        $result = Add-SslCertificateDetailToWinspectReport $winspectReportText @("Certificate file: gateway.crt", "Private key: Unencrypted")
        $resultLines = @($result -split $PHYSICAL_NEWLINE)

        $sagaCertHeaderIndex = [array]::IndexOf($resultLines, $sagaCertHeader)
        $summaryLineIndex = $sagaCertHeaderIndex + 1
        $resultLines[$summaryLineIndex + 1] | Should -Be "Certificate file: gateway.crt"
        $resultLines[$summaryLineIndex + 2] | Should -Be "Private key: Unencrypted"
        $resultLines[$summaryLineIndex + 3] | Should -Be ""
        $resultLines[$summaryLineIndex + 4] | Should -Be "###################### HOST IDENTITY #######################"
    }

    It "returns the original text unchanged if Winspect's SAGA SSL CERTIFICATE INFO section header can't be found" {
        # e.g. the section is omitted entirely by Winspect when neither a certificate file nor a
        # live hostname was available to check in the first place.
        $winspectReportText = @(
            "####################### REPORT INFO ########################",
            "Local time: 2026-08-30 12:00:00"
        ) -join $PHYSICAL_NEWLINE

        $result = Add-SslCertificateDetailToWinspectReport $winspectReportText @("Certificate file: gateway.crt")

        $result | Should -Be $winspectReportText
    }
}

Describe "Add-ExpirationsSectionToWinspectReport" {
    It "inserts the EXPIRATIONS section directly before Winspect's own CERTIFICATES header, as the report's 2nd block" {
        # Regression test: this section used to only ever appear after all of Winspect's own
        # sections (RESOURCE USAGE etc.) - Morten wanted it as the 2nd block overall, matching
        # ConfigInspector's own position for it, right after REPORT INFO.
        $certificatesHeader = Get-SectionHeader "CERTIFICATES"
        $winspectReportText = @(
            "####################### REPORT INFO ########################",
            "Local time: 2026-08-30 12:00:00",
            "",
            $certificatesHeader,
            "Certificate expirations: none"
        ) -join $PHYSICAL_NEWLINE
        Mock Get-DaysUntilSagaLicenseExpires { "Perpetual" }
        Mock Get-CertificateFromFile { [pscustomobject]@{ NotAfter = (Get-Date).AddDays(54).AddMinutes(5) } }
        $expirationsSectionRaw = Get-ExpirationsAndCapacityDepletionsReportSection ([pscustomobject]@{}) "C:\Saga\volumes\Traefik\certs\gateway.crt"

        $result = Add-ExpirationsSectionToWinspectReport $winspectReportText $expirationsSectionRaw
        $resultLines = @($result -split $PHYSICAL_NEWLINE)

        $expirationsHeaderIndex = [array]::IndexOf($resultLines, (Get-SectionHeader "EXPIRATIONS AND CAPACITY DEPLETIONS"))
        $certificatesHeaderIndex = [array]::IndexOf($resultLines, $certificatesHeader)
        $expirationsHeaderIndex | Should -BeGreaterThan -1
        $expirationsHeaderIndex | Should -BeLessThan $certificatesHeaderIndex
        $resultLines | Should -Contain "Days left of Saga license${FIELD_LABEL_SEPARATOR}Perpetual"
        $resultLines | Should -Contain "Days left of SSL certificate${FIELD_LABEL_SEPARATOR}54"
    }

    It "returns the original text unchanged if Winspect's CERTIFICATES section header can't be found" {
        $winspectReportText = @(
            "####################### REPORT INFO ########################",
            "Local time: 2026-08-30 12:00:00"
        ) -join $PHYSICAL_NEWLINE

        $result = Add-ExpirationsSectionToWinspectReport $winspectReportText "some expirations text"

        $result | Should -Be $winspectReportText
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

        $result = Get-SolrInfoReportSection "http://localhost/Dashboard/api" ""

        $result | Should -Match "Source reference count$([regex]::Escape($FIELD_LABEL_SEPARATOR))1,218,445"
    }

    It "reports 'Unavailable' (with the separator still present) when the API call fails" {
        Mock Get-SourceReferenceCount { throw "connection refused" }

        $result = Get-SolrInfoReportSection "http://localhost/Dashboard/api" ""

        $result | Should -Match "Source reference count$([regex]::Escape($FIELD_LABEL_SEPARATOR))Unavailable"
    }

    It "reports every field as 'Unavailable' when the install directory couldn't be resolved" {
        Mock Get-SourceReferenceCount { "1,218,445" }

        $result = Get-SolrInfoReportSection "http://localhost/Dashboard/api" ""

        $result | Should -Match "Solr index languages.*Unavailable"
        $result | Should -Match "Solr java memory.*Unavailable"
        $result | Should -Match "Solr java stack size.*Unavailable"
        $result | Should -Match "Solr index size.*Unavailable"
    }

    It "reads the Solr .env fields and index size when the install directory is known" {
        Mock Get-SourceReferenceCount { "1,218,445" }
        Mock Get-DotEnvValue {
            param($dotEnvFilePath, $key)
            if ($key -eq $SOLR_INDEX_LANGUAGES_KEY) { "en;nb" }
            elseif ($key -eq $SOLR_JAVA_MEM_KEY) { "-Xms8g -Xmx8g" }
            elseif ($key -eq $SOLR_JAVA_STACK_SIZE_KEY) { "-Xss256k" }
        }
        Mock Get-FormattedDirectorySize { "12.345 GB" }

        $result = Get-SolrInfoReportSection "http://localhost/Dashboard/api" "C:\Saga\"

        $result | Should -Match "Solr index languages.*en;nb"
        $result | Should -Match "Solr java memory.*-Xms8g -Xmx8g"
        $result | Should -Match "Solr java stack size.*-Xss256k"
        $result | Should -Match "Solr index size.*12\.345 GB"
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
        Mock Get-InstalledConnectorNames { @("fileserver", "exchange") }
        Mock Get-InstalledConnectorNamesFromPluginsDirectory { @("fileserver") }
        Mock Get-ConnectorNamesInUse { @("fileserver") }
        Mock Get-RunningConnectorNames { " - fileserver" }
    }

    It "includes the install directory, Saga version, branding, and gateway hostname when all are available" {
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com" "http://localhost/api/connector-broker/v1"

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
        Mock Get-InstalledConnectorNames { throw "connection refused" }
        Mock Get-RunningConnectorNames { throw "docker not available" }

        $result = Get-SagaInfoReportSection "" "" "http://localhost/api/connector-broker/v1"

        $result | Should -Match "Install directory.*Unavailable"
        $result | Should -Match "Saga version.*Unavailable"
        $result | Should -Match "Branding.*Unavailable"
        $result | Should -Match "Gateway hostname.*Unavailable"
        $result | Should -Match "Installed connectors \(plugins directory\).*Unavailable"
        $result | Should -Match "Installed connectors \(Management Console\).*Unavailable"
    }

    It "degrades the version and branding fields independently when the install directory is known but one lookup fails" {
        Mock Get-SagaVersion { throw "git.version not found" }
        Mock Get-DotEnvValue { "ayfie" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com" "http://localhost/api/connector-broker/v1"

        $result | Should -Match "Saga version.*Unavailable"
        $result | Should -Match "Branding.*ayfie"
    }

    It "reports 'Supported' when the detected OS is on Saga's supported list" {
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com" "http://localhost/api/connector-broker/v1"

        $result | Should -Match "OS supported by Saga.*Supported"
    }

    It "reports a warning (not a blocking error) when the detected OS is not on Saga's supported list" {
        Mock Get-OperatingSystemVersion { "Windows Server 2016 Standard (10.0.14393, build 14393)" }
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com" "http://localhost/api/connector-broker/v1"

        $result | Should -Match "OS supported by Saga.*WARNING.*not a version supported by Ayfie Index \(Saga\)"
    }

    It "reports 'Unavailable' for OS support if the OS itself can't be determined" {
        Mock Get-OperatingSystemVersion { throw "WMI unavailable" }
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com" "http://localhost/api/connector-broker/v1"

        $result | Should -Match "OS supported by Saga.*Unavailable"
    }

    It "includes the connector summary fields when everything succeeds" {
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-DotEnvValue { "custom" }

        $result = Get-SagaInfoReportSection "C:\Saga\" "engine.example.com" "http://localhost/api/connector-broker/v1"

        $result | Should -Match "Installed connectors \(Management Console\).*fileserver exchange"
        $result | Should -Match "Installed connectors \(plugins directory\).*fileserver"
        $result | Should -Match "Connectors in actual use.*fileserver"
        $result | Should -Match "Running connector containers"
        $result | Should -Match " - fileserver"
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

Describe "Get-DatabaseConnectorConfigurationsReportSection" {
    It "includes the connector definition summary under a DATABASE CONNECTOR CONFIGURATIONS heading" {
        Mock Get-ConnectorDefinitionSummary { "Connector: Tidemann`n<page name=`"Database`"></page>" }

        $result = Get-DatabaseConnectorConfigurationsReportSection "C:\Saga\"

        $result | Should -Match "DATABASE CONNECTOR CONFIGURATIONS"
        $result | Should -Match "Connector: Tidemann"
    }

    It "reports 'Unavailable' when the install directory couldn't be resolved" {
        Mock Get-ConnectorDefinitionSummary { throw "should not be called" }

        $result = Get-DatabaseConnectorConfigurationsReportSection ""

        $result | Should -Match "Unavailable"
    }

    It "degrades gracefully (no crash, 'Unavailable') when reading a definition file fails" {
        Mock Get-ConnectorDefinitionSummary { throw "access denied" }

        $result = Get-DatabaseConnectorConfigurationsReportSection "C:\Saga\"

        $result | Should -Match "Unavailable"
    }
}

Describe "Get-DataSourceUserSyncingReportSection" {
    It "includes the AD/Azure AD syncing flag when the install directory is known" {
        Mock Get-AdAndAzureAdSync { "true" }

        $result = Get-DataSourceUserSyncingReportSection "C:\Saga\"

        $result | Should -Match "DATA SOURCE USER SYNCING"
        $result | Should -Match "AD and Azure AD syncing.*true"
    }

    It "reports 'Unavailable' when the install directory couldn't be resolved" {
        Mock Get-AdAndAzureAdSync { throw "should not be called" }

        $result = Get-DataSourceUserSyncingReportSection ""

        $result | Should -Match "AD and Azure AD syncing.*Unavailable"
    }
}

Describe "Get-DatabaseInfoReportSection" {
    It "includes all five database fields when the install directory is known" {
        Mock Get-DatabaseInfo {
            [pscustomobject]@{ Type = "MSSQL"; Name = "Locator"; User = "postgres"; Server = "dbserver.example.com"; Port = "1433" }
        }

        $result = Get-DatabaseInfoReportSection "C:\Saga\"

        $result | Should -Match "DATABASE INFO"
        $result | Should -Match "Database type.*MSSQL"
        $result | Should -Match "Database name.*Locator"
        $result | Should -Match "Database user.*postgres"
        $result | Should -Match "Database server.*dbserver\.example\.com"
        $result | Should -Match "Database port.*1433"
    }

    It "reports every field as 'Unavailable' when the install directory couldn't be resolved" {
        Mock Get-DatabaseInfo { throw "should not be called" }

        $result = Get-DatabaseInfoReportSection ""

        $result | Should -Match "Database type.*Unavailable"
        $result | Should -Match "Database port.*Unavailable"
    }

    It "degrades gracefully to 'Unavailable' when the lookup itself fails" {
        Mock Get-DatabaseInfo { throw "file not found" }

        $result = Get-DatabaseInfoReportSection "C:\Saga\"

        $result | Should -Match "Database type.*Unavailable"
    }
}

Describe "Get-SupervisorInfoReportSection" {
    It "includes the report engine container status, license, and Lingo configuration" {
        Mock Get-ContainerStatus { "Running" }
        Mock Test-HasSagaLicenseCapability { "Has license" }
        Mock Get-LingoDataTypeAndLanguage { "nb (regular, not PII)" }

        $result = Get-SupervisorInfoReportSection "C:\Saga\" ([pscustomobject]@{ Features = "Report Engine" })

        $result | Should -Match "SUPERVISOR INFO"
        $result | Should -Match "Report engine container.*Running"
        $result | Should -Match "Report engine license.*Has license"
        $result | Should -Match "Report engine Lingo configuration.*nb \(regular, not PII\)"
    }

    It "reports 'Unavailable' for the Lingo configuration when the install directory couldn't be resolved" {
        Mock Get-ContainerStatus { "Not running" }
        Mock Test-HasSagaLicenseCapability { "No license" }
        Mock Get-LingoDataTypeAndLanguage { throw "should not be called" }

        $result = Get-SupervisorInfoReportSection "" $null

        $result | Should -Match "Report engine Lingo configuration.*Unavailable"
    }

    It "degrades gracefully to 'Unavailable' when the container status check itself fails" {
        Mock Get-ContainerStatus { throw "docker not available" }
        Mock Test-HasSagaLicenseCapability { "Has license" }
        Mock Get-LingoDataTypeAndLanguage { "nb (regular, not PII)" }

        $result = Get-SupervisorInfoReportSection "C:\Saga\" ([pscustomobject]@{ Features = "Report Engine" })

        $result | Should -Match "Report engine container.*Unavailable"
    }
}

Describe "Get-PersonalAssistantReportSection" {
    It "includes all seven fields when the Saga version is older than the model-fields cutoff" {
        Mock Get-SagaVersion { "6.4.0" }
        Mock Get-PersonalAssistantInfo {
            [pscustomobject]@{
                Mode = "full"; MainModel = "gpt-4o"; MainModelDisplayName = "GPT-4o"
                HighQualityModel = "gpt-4o-hq"; HighQualityModelDisplayName = "GPT-4o HQ"
                HighQualityPlusModel = "gpt-4o-hq-plus"; HighQualityPlusModelDisplayName = "GPT-4o HQ+"
            }
        }

        $result = Get-PersonalAssistantReportSection "C:\Saga\"

        $result | Should -Match "PERSONAL ASSISTANT"
        $result | Should -Match "Operational mode.*full"
        $result | Should -Match "Main model.*gpt-4o"
        $result | Should -Match "Main model display name.*GPT-4o"
        $result | Should -Match "High quality model.*gpt-4o-hq"
        $result | Should -Match "High quality plus model.*gpt-4o-hq-plus"
    }

    It "omits the model fields entirely once the Saga version reaches the cutoff" {
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-PersonalAssistantInfo {
            [pscustomobject]@{
                Mode = "full"; MainModel = "gpt-4o"; MainModelDisplayName = "GPT-4o"
                HighQualityModel = $null; HighQualityModelDisplayName = $null
                HighQualityPlusModel = $null; HighQualityPlusModelDisplayName = $null
            }
        }

        $result = Get-PersonalAssistantReportSection "C:\Saga\"

        $result | Should -Match "Operational mode.*full"
        $result | Should -Not -Match "Main model"
    }

    It "reports 'Unavailable' and still includes the model fields when the install directory couldn't be resolved" {
        Mock Get-PersonalAssistantInfo { throw "should not be called" }

        $result = Get-PersonalAssistantReportSection ""

        $result | Should -Match "Operational mode.*Unavailable"
        $result | Should -Match "Main model"
    }

    It "degrades gracefully to 'Unavailable' when the lookup itself fails" {
        Mock Get-SagaVersion { "7.19.0" }
        Mock Get-PersonalAssistantInfo { throw "file not found" }

        $result = Get-PersonalAssistantReportSection "C:\Saga\"

        $result | Should -Match "Operational mode.*Unavailable"
    }
}

Describe "Get-LingoInfoReportSection" {
    It "includes all Lingo fields, container status, and both license checks when everything succeeds" {
        Mock Get-LingoInfo {
            [pscustomobject]@{
                Enabled = "true"; DataTypeAndLanguage = "nb (regular, not PII)"; Threads = "4"
                RecycleMemoryThresholdMb = "2048"; RecycleRuns = "1000"; RecycleTimeSeconds = "3600"
            }
        }
        Mock Get-ContainerStatus { "Running" }
        Mock Test-HasSagaLicenseCapability { "Has license" }

        $result = Get-LingoInfoReportSection "C:\Saga\" ([pscustomobject]@{ Features = "Lingo Standard`nLingo GDPR" })

        $result | Should -Match "LINGO INFO"
        $result | Should -Match "Lingo enabled.*true"
        $result | Should -Match "Lingo container.*Running"
        $result | Should -Match "Lingo standard license.*Has license"
        $result | Should -Match "Lingo GDPR license.*Has license"
        $result | Should -Match "Lingo language \(and data type\).*nb \(regular, not PII\)"
        $result | Should -Match "Lingo threads.*4"
        $result | Should -Match "Lingo recycle memory threshold.*2048"
        $result | Should -Match "Lingo recycle runs.*1000"
        $result | Should -Match "Lingo recycle time \(seconds\).*3600"
    }

    It "reports 'Unavailable' for the .env-derived fields when the install directory couldn't be resolved" {
        Mock Get-LingoInfo { throw "should not be called" }
        Mock Get-ContainerStatus { "Not running" }
        Mock Test-HasSagaLicenseCapability { "Unavailable" }

        $result = Get-LingoInfoReportSection "" $null

        $result | Should -Match "Lingo enabled.*Unavailable"
        $result | Should -Match "Lingo container.*Not running"
    }

    It "degrades gracefully to 'Unavailable' when the container status check fails" {
        Mock Get-LingoInfo {
            [pscustomobject]@{
                Enabled = "true"; DataTypeAndLanguage = "nb (regular, not PII)"; Threads = "4"
                RecycleMemoryThresholdMb = "2048"; RecycleRuns = "1000"; RecycleTimeSeconds = "3600"
            }
        }
        Mock Get-ContainerStatus { throw "docker not available" }
        Mock Test-HasSagaLicenseCapability { "Has license" }

        $result = Get-LingoInfoReportSection "C:\Saga\" ([pscustomobject]@{ Features = "Lingo Standard" })

        $result | Should -Match "Lingo container.*Unavailable"
    }
}

Describe "Get-DockerImagesReportSection" {
    It "includes the image list under a DOCKER IMAGES CURRENTLY IN USE heading" {
        Mock Get-DockerImagesOfRunningContainers { "ayfiehub/locator:7.3.1`nayfiehub/solr:7.4.0" }

        $result = Get-DockerImagesReportSection

        $result | Should -Match "DOCKER IMAGES CURRENTLY IN USE"
        $result | Should -Match "ayfiehub/locator:7\.3\.1"
    }

    It "degrades gracefully (no crash, 'Unavailable') when the docker call fails" {
        Mock Get-DockerImagesOfRunningContainers { throw "docker not available" }

        $result = Get-DockerImagesReportSection

        $result | Should -Match "Unavailable"
    }
}

Describe "Get-BackupsReportSection" {
    It "includes count, latest backup, and total size when backups exist" {
        Mock Get-BackupsSummary {
            [pscustomobject]@{ Count = 2; LatestBackup = "2026-03-21 17:59"; TotalSize = "151.751 MB" }
        }

        $result = Get-BackupsReportSection "C:\Saga\"

        $result | Should -Match "BACKUPS"
        $result | Should -Match "Number of backups.*2"
        $result | Should -Match "Latest backup.*2026-03-21 17:59"
        $result | Should -Match "Total size.*151\.751 MB"
    }

    It "reports only the zero count, with no latest/size fields, when there are no backups" {
        Mock Get-BackupsSummary {
            [pscustomobject]@{ Count = 0; LatestBackup = $null; TotalSize = $null }
        }

        $result = Get-BackupsReportSection "C:\Saga\"

        $result | Should -Match "Number of backups.*0"
        $result | Should -Not -Match "Latest backup"
    }

    It "reports 'Unavailable' when the install directory couldn't be resolved" {
        Mock Get-BackupsSummary { throw "should not be called" }

        $result = Get-BackupsReportSection ""

        $result | Should -Match "Number of backups.*Unavailable"
    }
}

Describe "Get-SagaLicenseInfoReportSection" {
    # Takes the already-resolved summary as a parameter now, rather than resolving it internally -
    # see the note on the function itself for why (Add-CustomerNameToReportInfo and
    # Get-ExpirationsAndCapacityDepletionsReportSection need the same data).

    It "includes all six fields when the license summary succeeds" {
        $licenseSummary = [pscustomobject]@{
            CustomerId = "1234567"; ActivationDates = "2022-06-01T15:12:58Z"
            ExpirationDates = "2027-01-31T13:08:22Z"; UserCapacity = 100; DocumentCapacity = 1000000
            Features = "Connector: File Server Connector"
        }

        $result = Get-SagaLicenseInfoReportSection $licenseSummary

        $result | Should -Match "SAGA LICENSE INFO"
        $result | Should -Match "Customer Id.*1234567"
        $result | Should -Match "Activation date \(utc\).*2022-06-01T15:12:58Z"
        $result | Should -Match "Expiration date \(utc\).*2027-01-31T13:08:22Z"
        $result | Should -Match "User capacity.*100"
        $result | Should -Match "Document capacity.*1000000"
        $result | Should -Match "Connector: File Server Connector"
    }

    It "reports every field as 'Unavailable' when the summary is null (resolution failed entirely)" {
        $result = Get-SagaLicenseInfoReportSection $null

        $result | Should -Match "Customer Id.*Unavailable"
        $result | Should -Match "User capacity.*Unavailable"
    }

    It "still shows customerId as 'Unavailable'-free when only some fields resolve" {
        $licenseSummary = [pscustomobject]@{
            CustomerId = "1234567"; ActivationDates = $null; ExpirationDates = $null
            UserCapacity = $null; DocumentCapacity = $null; Features = $null
        }

        $result = Get-SagaLicenseInfoReportSection $licenseSummary

        $result | Should -Match "Customer Id.*1234567"
        $result | Should -Match "User capacity.*Unavailable"
    }
}

Describe "Get-ExpirationsAndCapacityDepletionsReportSection" {
    It "includes the Saga license and SSL certificate days-left figures under the section heading" {
        # Regression test: the SSL certificate half used to be left out of this section entirely
        # (the days-left figure was only ever visible tucked inside SAGA CERTIFICATE's one-line
        # summary) - confirmed missing versus ConfigInspector's own "Days left of SSL certificate"
        # line, which sits right here, during a real KTH comparison.
        Mock Get-DaysUntilSagaLicenseExpires { 94 }
        # A few minutes' buffer past the 54-day mark, not exactly on it - the function computes its
        # own "now" a moment after this mock's "now", and without a buffer that tiny gap can push
        # the truncated day count down to 53, making the test flaky.
        Mock Get-CertificateFromFile { [pscustomobject]@{ NotAfter = (Get-Date).AddDays(54).AddMinutes(5) } }

        $result = Get-ExpirationsAndCapacityDepletionsReportSection ([pscustomobject]@{}) "C:\Saga\volumes\Traefik\certs\gateway.crt"

        $result | Should -Match "EXPIRATIONS AND CAPACITY DEPLETIONS"
        $result | Should -Match "Days left of Saga license.*94"
        $result | Should -Match "Days left of SSL certificate.*54"
    }

    It "degrades gracefully (no crash, 'Unavailable') when either check fails" {
        Mock Get-DaysUntilSagaLicenseExpires { throw "should not normally throw, but handled anyway" }
        Mock Get-CertificateFromFile { throw "file not found" }

        $result = Get-ExpirationsAndCapacityDepletionsReportSection ([pscustomobject]@{}) "C:\Saga\volumes\Traefik\certs\gateway.crt"

        $result | Should -Match "Days left of Saga license.*Unavailable"
        $result | Should -Match "Days left of SSL certificate.*Unavailable"
    }

    It "reports 'Unavailable' for the SSL certificate when no certificate file path is known" {
        Mock Get-DaysUntilSagaLicenseExpires { 94 }
        Mock Get-CertificateFromFile { throw "should not be called" }

        $result = Get-ExpirationsAndCapacityDepletionsReportSection ([pscustomobject]@{}) ""

        $result | Should -Match "Days left of SSL certificate.*Unavailable"
    }
}

Describe "Add-CustomerNameToReportInfo" {
    It "inserts a Customer line directly after the REPORT INFO section header" {
        $winspectReportText = @(
            "####################### REPORT INFO ########################",
            "Local time: 2026-08-28 17:16:02",
            "User: kth-search-prod\prod-ayfie-admin"
        ) -join $PHYSICAL_NEWLINE

        $result = Add-CustomerNameToReportInfo $winspectReportText "Acme Corp"
        $resultLines = @($result -split $PHYSICAL_NEWLINE)

        $resultLines[0] | Should -Match "REPORT INFO"
        $resultLines[1] | Should -Match "^Customer.*Acme Corp"
        $resultLines[2] | Should -Be "Local time: 2026-08-28 17:16:02"
    }

    It "returns the original text unchanged (no 'Customer' line at all) when there's no customer name" {
        $winspectReportText = @("####################### REPORT INFO ########################", "Local time: x") -join $PHYSICAL_NEWLINE

        Add-CustomerNameToReportInfo $winspectReportText $null | Should -Be $winspectReportText
    }

    It "returns the original text unchanged if the REPORT INFO section header can't be found" {
        $winspectReportText = @("Some unrelated report text", "with no REPORT INFO header at all") -join $PHYSICAL_NEWLINE

        Add-CustomerNameToReportInfo $winspectReportText "Acme Corp" | Should -Be $winspectReportText
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

Describe "Get-TemporaryEnvFileChangesReportSection" {
    It "includes removed, added, and modified variables under the section heading" {
        Mock Get-EnvConfigDiff {
            [pscustomobject]@{ Removed = "AYFIE_REMOVED_VAR"; Added = "AYFIE_ADDED_VAR (new)"; Modified = "AYFIE_SAGA_BRANDING_KEY (custom)" }
        }

        $result = Get-TemporaryEnvFileChangesReportSection "C:\Saga\"

        $result | Should -Match "TEMPORARY \.ENV FILE CHANGES"
        $result | Should -Match "Removed variables.*AYFIE_REMOVED_VAR"
        $result | Should -Match "Added variables.*AYFIE_ADDED_VAR \(new\)"
        $result | Should -Match "Modified variables.*AYFIE_SAGA_BRANDING_KEY \(custom\)"
    }

    It "reports 'Unavailable' for all three fields when the install directory couldn't be resolved" {
        Mock Get-EnvConfigDiff { throw "should not be called" }

        $result = Get-TemporaryEnvFileChangesReportSection ""

        $result | Should -Match "Removed variables.*Unavailable"
        $result | Should -Match "Added variables.*Unavailable"
        $result | Should -Match "Modified variables.*Unavailable"
    }

    It "degrades gracefully to 'Unavailable' when the diff itself fails (e.g. Ayfie.Saga.zip missing)" {
        Mock Get-EnvConfigDiff { throw "zip not found" }

        $result = Get-TemporaryEnvFileChangesReportSection "C:\Saga\"

        $result | Should -Match "Removed variables.*Unavailable"
    }
}
