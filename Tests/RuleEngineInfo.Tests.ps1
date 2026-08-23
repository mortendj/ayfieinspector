BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../../Winspect/src/ReportFormatting.ps1"
    . "$PSScriptRoot/../src/DashboardApi.ps1"
    . "$PSScriptRoot/../src/RuleEngineInfo.ps1"

    function New-FakeRule($ruleName, $ruleType, $targetRunner, $definition = "<rules></rules>") {
        return [pscustomobject]@{
            RuleName         = $ruleName
            RuleType         = $ruleType
            Version          = "1"
            SortOrder        = 10
            LastModifiedDate = "2026-01-01T00:00:00Z"
            ConnectorTypeId  = $null
            TargetRunner     = $targetRunner
            Definition       = $definition
        }
    }
}

Describe "Get-RuleEngineRules" {
    # Mock returns via `return ,@(...)`, deliberately matching the exact comma-wrapped return
    # shape Write-ReturnValue produces in the real Get-DashboardApiResponse. This is a direct
    # regression test for a real bug found on a production host: an earlier version wrapped this
    # mocked call in `@(...)` directly instead of assigning to a variable first, which nested the
    # array one level deeper instead of flattening it - every rule then collapsed into one
    # space-joined blob via PowerShell's member-enumeration. If that regresses, this test fails by
    # returning a count of 1 (one nested array) instead of 3 (three real items).

    It "returns a flat array, not a nested one, for multiple rules" {
        # Newline-separated, not comma-separated - a trailing comma after an unparenthesized
        # multi-argument command call is itself a line-continuation trigger in PowerShell, which
        # would silently fold the next call into an array-valued argument of this one instead of
        # producing a separate array element.
        $rules = @(
            New-FakeRule "Rule A" "system" "index"
            New-FakeRule "Rule B" "custom" "index"
            New-FakeRule "Rule C" "custom" "search"
        )
        Mock Get-DashboardApiResponse { return ,$rules }

        # Assigned to a variable first, not wrapped in @(...) at the call site - Get-RuleEngineRules
        # itself already returns the correct array shape via its own Write-ReturnValue; wrapping the
        # call directly would nest it one level deeper, the same hazard as the real production bug.
        $result = Get-RuleEngineRules "http://localhost/Dashboard/api"

        $result.Count | Should -Be 3
        $result.RuleName | Should -Contain "Rule A"
        $result.RuleName | Should -Contain "Rule C"
    }

    It "returns a single-element array as an actual array, not unwrapped to a scalar" {
        $rules = @(New-FakeRule "Only Rule" "custom" "index")
        Mock Get-DashboardApiResponse { return ,$rules }

        $result = Get-RuleEngineRules "http://localhost/Dashboard/api"

        $result.Count | Should -Be 1
        $result[0].RuleName | Should -Be "Only Rule"
    }

    It "returns an empty array, not null, when there are no rules" {
        Mock Get-DashboardApiResponse { return ,@() }

        $result = Get-RuleEngineRules "http://localhost/Dashboard/api"

        $result.Count | Should -Be 0
    }
}

Describe "Get-RulesSummary" {
    It "reports 'No rules found' for an empty array" {
        Get-RulesSummary @() | Should -Match "No rules found"
    }

    It "includes each rule's name, type, and definition" {
        $rules = @(New-FakeRule "Map department field" "custom" "index" "<rules><rule name=`"x`" /></rules>")

        $result = Get-RulesSummary $rules

        $result | Should -Match "Map department field"
        $result | Should -Match "RuleType$([regex]::Escape($FIELD_LABEL_SEPARATOR))custom"
        $result | Should -Match "<rule name=`"x`" />"
    }

    It "includes every rule when given more than one" {
        $rules = @(
            (New-FakeRule "First Rule" "custom" "index"),
            (New-FakeRule "Second Rule" "custom" "index")
        )

        $result = Get-RulesSummary $rules

        $result | Should -Match "First Rule"
        $result | Should -Match "Second Rule"
    }
}
