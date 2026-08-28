BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../../Winspect/src/ReportFormatting.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/ConnectorApi.ps1"
    . "$PSScriptRoot/../src/DataSourceConnectionInfo.ps1"

    Initialize-OutputFormatLayout "text"

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

Describe "Get-ConnectionPropertyAsLines" {
    It "renders a scalar property inline, on a single line" {
        $result = Get-ConnectionPropertyAsLines "sharingGroupKey" "abc123" 1

        $result.Count | Should -Be 1
        $result[0] | Should -Match "sharingGroupKey: abc123"
    }

    It "renders a nested object's own properties on indented lines beneath its name" {
        $security = [pscustomobject]@{ authRealm = "saga"; requiresAuthentication = $true }

        $result = Get-ConnectionPropertyAsLines "security" $security 1
        $resultText = $result -join "`n"

        $result[0] | Should -Match "security:"
        $resultText | Should -Match "authRealm: saga"
        $resultText | Should -Match "requiresAuthentication: True"
    }

    It "renders an array of nested objects, each contributing its own properties" {
        $repositories = @(
            [pscustomobject]@{ name = "Repo1"; path = "\\host\Repo1" },
            [pscustomobject]@{ name = "Repo2"; path = "\\host\Repo2" }
        )

        $result = Get-ConnectionPropertyAsLines "repositories" $repositories 1
        $resultText = $result -join "`n"

        $result[0] | Should -Match "repositories:"
        $resultText | Should -Match "name: Repo1"
        $resultText | Should -Match "name: Repo2"
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

    It "includes extra fields the connection API happens to return - e.g. repositories, security - rather than silently dropping them" {
        # Regression coverage for the older tool this is ported from, which dumps every property
        # of the raw connection object generically instead of hand-picking a fixed field list -
        # this project previously only rendered displayName/connectorName/isEnabled/documentCount.
        $connection = [pscustomobject]@{
            displayName = "NetData"; connectorName = "fileserver"; isEnabled = $true; documentCount = 44907
            security = [pscustomobject]@{ authRealm = "saga" }
            repositories = @([pscustomobject]@{ name = "Repo1" })
        }

        $result = Get-DataSourceConnectionSummary $connection ""

        $result | Should -Match "security:"
        $result | Should -Match "authRealm: saga"
        $result | Should -Match "repositories:"
        $result | Should -Match "name: Repo1"
    }

    It "never renders the well-known fields a second time as generic extras" {
        $connection = [pscustomobject]@{
            id = 1; displayName = "NetData"; connectorName = "fileserver"; isEnabled = $true; documentCount = 44907
        }

        $result = Get-DataSourceConnectionSummary $connection ""
        $idOccurrences = @([regex]::Matches($result, "(?m)^id:")).Count

        $idOccurrences | Should -Be 0
    }

    It "skips a null-valued extra field entirely rather than rendering an empty line for it" {
        $connection = [pscustomobject]@{
            displayName = "NetData"; connectorName = "fileserver"; isEnabled = $true; documentCount = 44907
            repositoryStates = $null
        }

        $result = Get-DataSourceConnectionSummary $connection ""

        $result | Should -Not -Match "repositoryStates"
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
