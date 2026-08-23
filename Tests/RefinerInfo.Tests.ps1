BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../../Winspect/src/ReportFormatting.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/DashboardApi.ps1"
    . "$PSScriptRoot/../src/RefinerInfo.ps1"

    function New-FakeRefiner($refinerName, $displayName, $fieldName, $selectionLimit = 1000, $enabled = $true, $sortOrder = 1) {
        return [pscustomobject]@{
            RefinerName    = $refinerName
            DisplayName    = $displayName
            FieldName      = $fieldName
            FacetType      = "FacetField"
            SelectionLimit = $selectionLimit
            Enabled        = $enabled
            SortOrder      = $sortOrder
        }
    }
}

Describe "Get-CustomRefiners" {
    # Same nesting-bug regression shape as RuleEngineInfo.Tests.ps1 - see that file for the full
    # explanation. `return ,$refiners` matches Write-ReturnValue's real shape exactly.

    It "returns a flat array of only the non-default refiners" {
        $refiners = @(
            New-FakeRefiner "DateModified" "Date Modified" "search_date"   # a built-in default
            New-FakeRefiner "Department" "Department" "via_ssimd_department"
        )
        Mock Get-DashboardApiResponse { return ,$refiners }

        # Assigned to a variable first, not wrapped in @(...) at the call site - Get-CustomRefiners
        # itself already returns the correct array shape via its own Write-ReturnValue; wrapping the
        # call directly would nest it one level deeper, the same hazard as the real production bug.
        $result = Get-CustomRefiners "http://localhost/Dashboard/api"

        $result.Count | Should -Be 1
        $result[0].RefinerName | Should -Be "Department"
    }

    It "returns an empty array, not null, when every refiner is a built-in default" {
        $refiners = @(New-FakeRefiner "DateModified" "Date Modified" "search_date")
        Mock Get-DashboardApiResponse { return ,$refiners }

        $result = Get-CustomRefiners "http://localhost/Dashboard/api"

        $result.Count | Should -Be 0
    }

    It "keeps multiple custom refiners as separate items, not one nested blob" {
        $refiners = @(
            New-FakeRefiner "Department" "Department" "via_ssimd_department"
            New-FakeRefiner "School" "School" "via_ssimd_kth_school"
        )
        Mock Get-DashboardApiResponse { return ,$refiners }

        $result = Get-CustomRefiners "http://localhost/Dashboard/api"

        $result.Count | Should -Be 2
        $result.RefinerName | Should -Contain "Department"
        $result.RefinerName | Should -Contain "School"
    }
}

Describe "Get-RefinersSummary" {
    It "reports 'No custom refiners found' for an empty array" {
        Get-RefinersSummary @() | Should -Match "No custom refiners found"
    }

    It "includes each refiner's display name, field name, and settings" {
        $refiners = @(New-FakeRefiner "Department" "Department" "via_ssimd_department" 500 $false 7)

        $result = Get-RefinersSummary $refiners

        $result | Should -Match "Department"
        $result | Should -Match "via_ssimd_department"
        $result | Should -Match "SelectionLimit$([regex]::Escape($FIELD_LABEL_SEPARATOR))500"
        $result | Should -Match "Enabled$([regex]::Escape($FIELD_LABEL_SEPARATOR))False"
    }

    It "includes every refiner when given more than one" {
        $refiners = @(
            (New-FakeRefiner "Department" "Department" "via_ssimd_department"),
            (New-FakeRefiner "School" "School" "via_ssimd_kth_school")
        )

        $result = Get-RefinersSummary $refiners

        $result | Should -Match "Department"
        $result | Should -Match "School"
    }
}
