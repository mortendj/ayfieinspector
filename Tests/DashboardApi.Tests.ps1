BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/DashboardApi.ps1"
}

Describe "Get-DashboardApiResponse" {
    It "requests the given endpoint under the given root URL and returns just the Data field" {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ Message = "Success"; HttpStatusCode = 200; Data = @("a", "b", "c") }
        } -ParameterFilter { $Uri -eq "http://localhost/Dashboard/api/rules" }

        $result = Get-DashboardApiResponse "http://localhost/Dashboard/api" "rules"

        @($result).Count | Should -Be 3
        $result | Should -Contain "a"
    }
}

Describe "Get-SourceReferenceCount" {
    # Assigns Get-DashboardApiResponse's result to a variable first inside Get-SourceReferenceCount
    # itself - this mock deliberately returns a bare scalar (not wrapped via `return ,$x`), matching
    # what the real function actually returns for this endpoint (a plain number, not an array), so
    # this test only exercises the number-formatting logic, not the array-nesting hazard (that's
    # covered separately in RuleEngineInfo.Tests.ps1/RefinerInfo.Tests.ps1, where the real endpoint
    # actually returns an array).

    It "formats a large count with thousands separators" {
        Mock Get-DashboardApiResponse { 1218445 }

        Get-SourceReferenceCount "http://localhost/Dashboard/api" | Should -Be "1,218,445"
    }

    It "does not add a thousands separator below 1000" {
        Mock Get-DashboardApiResponse { 42 }

        Get-SourceReferenceCount "http://localhost/Dashboard/api" | Should -Be "42"
    }
}
