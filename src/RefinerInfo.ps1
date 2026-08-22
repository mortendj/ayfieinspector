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
            $lines += "$INDENTATION${INDENTATION}RefinerName$FIELD_LABEL_SEPARATOR$($refiner.RefinerName)"
            $lines += "$INDENTATION${INDENTATION}FieldName$FIELD_LABEL_SEPARATOR$($refiner.FieldName)"
            $lines += "$INDENTATION${INDENTATION}FacetType$FIELD_LABEL_SEPARATOR$($refiner.FacetType)"
            $lines += "$INDENTATION${INDENTATION}SelectionLimit$FIELD_LABEL_SEPARATOR$($refiner.SelectionLimit)"
            $lines += "$INDENTATION${INDENTATION}Enabled$FIELD_LABEL_SEPARATOR$($refiner.Enabled)"
            $lines += "$INDENTATION${INDENTATION}SortOrder$FIELD_LABEL_SEPARATOR$($refiner.SortOrder)"
            $blocks += ($lines -join $LOGICAL_NEWLINE)
        }
        $output = ($blocks -join ($LOGICAL_NEWLINE + $LOGICAL_NEWLINE))
    }
    Write-ReturnValue $output
}
