BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/ConnectorApi.ps1"
}

Describe "Get-ConnectorApiResponse" {
    It "requests the given endpoint under the given root URL and returns the raw response, with no .Data envelope" {
        # Regression test: unlike the Dashboard API, the connector-broker API returns its payload
        # directly - a real bug (found live against a production host) applied the Dashboard API's
        # .Data-unwrapping convention here too, which silently turned every connector name into
        # $null instead of throwing, since PowerShell auto-enumerates .Data across an array's
        # elements rather than erroring when the property doesn't exist.
        Mock Invoke-RestMethod {
            @("a", "b")
        } -ParameterFilter { $Uri -eq "http://localhost/api/connector-broker/v1/connectors/installed" }

        $result = Get-ConnectorApiResponse "http://localhost/api/connector-broker/v1" "connectors/installed"

        @($result).Count | Should -Be 2
        $result | Should -Contain "a"
    }
}

Describe "Get-InstalledConnectorNames" {
    # Not `$result = @(Get-InstalledConnectorNames ...)` anywhere below - see the note in
    # RuleEngineInfo.ps1's Get-RuleEngineRules for why wrapping a Write-ReturnValue-based call
    # directly in @(...) nests the real array one level deeper instead of flattening it.

    It "extracts the connectorName property from each installed connector" {
        Mock Get-ConnectorApiResponse {
            @(
                [pscustomobject]@{ connectorName = "fileserver" },
                [pscustomobject]@{ connectorName = "exchange" }
            )
        }

        $result = Get-InstalledConnectorNames "http://localhost/api/connector-broker/v1"

        # Not `$result | Should -Be @(...)` - piping an array into Should -Be unrolls it and
        # compares element-by-element against the whole expected array, not the array as a whole.
        $result.Count | Should -Be 2
        $result[0] | Should -Be "fileserver"
        $result[1] | Should -Be "exchange"
    }

    It "returns an empty array, not null, when nothing is installed" {
        Mock Get-ConnectorApiResponse { @() }

        $result = Get-InstalledConnectorNames "http://localhost/api/connector-broker/v1"

        $result.Count | Should -Be 0
    }
}

Describe "Get-ConnectorConnections" {
    It "queries Connections/<connectorName>" {
        Mock Get-ConnectorApiResponse {
            @([pscustomobject]@{ id = 1; displayName = "NetData" })
        } -ParameterFilter { $endpoint -eq "Connections/fileserver" }

        $result = Get-ConnectorConnections "http://localhost/api/connector-broker/v1" "fileserver"

        $result[0].displayName | Should -Be "NetData"
    }
}

Describe "Get-ConnectionSettings" {
    It "queries Connections/<connectionId>/settings" {
        Mock Get-ConnectorApiResponse {
            @([pscustomobject]@{ settingName = "RequestTimeout"; settingValue = "60" })
        } -ParameterFilter { $endpoint -eq "Connections/6/settings" }

        $result = Get-ConnectionSettings "http://localhost/api/connector-broker/v1" 6

        $result[0].settingName | Should -Be "RequestTimeout"
    }
}
