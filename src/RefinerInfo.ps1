function Get-CustomRefiners($dashboardApiRootUrl) {
    Write-FunctionCallLog $PSBoundParameters
    # Assigned to a variable first, not wrapped directly around the call, and re-assigned before
    # piping - same reasoning as Get-RuleEngineRules: @() around the call itself (or piping
    # directly from it) nests the array instead of flattening it. Matches the established safe
    # pattern from Certificates.ps1 in Winspect.
    $refiners = Get-DashboardApiResponse $dashboardApiRootUrl "refiners"
    $refiners = @($refiners | Where-Object { $_.RefinerName -notin $DEFAULT_REFINERS })
    Write-ReturnValue $refiners
}

function Get-RefinersSummary($refiners) {
    Write-FunctionCallLog $PSBoundParameters
    if ($refiners.Count -eq 0) {
        $output = "${INDENTATION}No custom refiners found"
    } else {
        $blocks = @()
        foreach ($refiner in $refiners) {
            $lines = @()
            $lines += "$INDENTATION$($refiner.DisplayName)"
            # Every property the Dashboard API returns, not a hand-picked subset - matches
            # ConfigInspector's own CUSTOM REFINERS section (a generic per-property dump via
            # Get-ItemAsString), which showed ~20 fields (ParentRefiner, IsHierarchical, Tags,
            # FacetsSortOrder, RangeType, etc.) this used to drop silently. Property order follows
            # whatever order the API/JSON returned them in, same as ConfigInspector.
            foreach ($property in $refiner.psobject.Properties) {
                if ($property.Name -eq "DisplayName") {
                    continue
                }
                $value = $property.Value
                if ($null -eq $value) {
                    $value = '$null'
                } elseif ($value -is [System.Array]) {
                    $value = $value -join ", "
                }
                $lines += "$INDENTATION${INDENTATION}$($property.Name)$FIELD_LABEL_SEPARATOR$value"
            }
            $blocks += ($lines -join $LOGICAL_NEWLINE)
        }
        $output = ($blocks -join ($LOGICAL_NEWLINE + $LOGICAL_NEWLINE))
    }
    Write-ReturnValue $output
}
