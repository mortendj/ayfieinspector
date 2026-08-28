BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/ConnectorApi.ps1"
    . "$PSScriptRoot/../src/DataSourceConnectionInfo.ps1"

    function New-FakeSetting($name, $value) {
        return [pscustomobject]@{ settingName = $name; settingValue = $value }
    }
}

Describe "Get-SecurityClearedConnectionSettings" {
    It "drops settings matching a sensitive token entirely, rather than masking the value" {
        # Regression case: a real production P360Online connection had an "AuthKey" setting that
        # wasn't caught until "Key" was added to the token list here - see
        # project_ayfieinspector_gateway_cert_feature.md for the full finding.
        $settings = @(
            (New-FakeSetting "AuthKey" "abc123"),
            (New-FakeSetting "ClientId" "Ar0xgd4RtWLt3SRViqupTA==")
        )

        $result = Get-SecurityClearedConnectionSettings $settings @("Token", "Secret", "Password", "CompanyGuid", "Key")

        $result | Should -Not -Match "abc123"
        $result | Should -Not -Match "AuthKey"
        $result | Should -Match "ClientId=Ar0xgd4RtWLt3SRViqupTA=="
    }

    It "returns an empty string when every setting is sensitive" {
        $settings = @((New-FakeSetting "ApiKey" "xyz"))

        Get-SecurityClearedConnectionSettings $settings @("Key") | Should -Be ""
    }
}

Describe "Get-DataSourceConnectionSummary" {
    It "includes the display name, connector name, enabled state, document count, and settings" {
        $connection = [pscustomobject]@{
            displayName = "NetData"; connectorName = "fileserver"; isEnabled = $true; documentCount = 44907
        }

        $result = Get-DataSourceConnectionSummary $connection "StartPath=\\host\NetData"

        $result | Should -Match "NetData \(fileserver\)"
        $result | Should -Match "Enabled: True"
        $result | Should -Match "Document count: 44907"
        $result | Should -Match "StartPath=\\\\host\\NetData"
    }
}

Describe "Get-DataSourceConnectionsSummary" {
    It "reports 'No data source connections found' when no connectors are installed" {
        Mock Get-InstalledConnectorNames { @() }

        Get-DataSourceConnectionsSummary "http://localhost/api/connector-broker/v1" | Should -Be "No data source connections found"
    }

    It "includes every connection across every installed connector" {
        Mock Get-InstalledConnectorNames { @("fileserver", "exchange") }
        Mock Get-ConnectorConnections {
            param($connectorApiRootUrl, $connectorName)
            if ($connectorName -eq "fileserver") {
                @([pscustomobject]@{ id = 1; displayName = "NetData"; connectorName = "fileserver"; isEnabled = $true; documentCount = 100 })
            } else {
                @([pscustomobject]@{ id = 2; displayName = "Exchange"; connectorName = "exchange"; isEnabled = $true; documentCount = 200 })
            }
        }
        Mock Get-ConnectionSettings { @() }

        $result = Get-DataSourceConnectionsSummary "http://localhost/api/connector-broker/v1"

        $result | Should -Match "NetData \(fileserver\)"
        $result | Should -Match "Exchange \(exchange\)"
    }
}
