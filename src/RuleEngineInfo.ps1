function Get-RuleEngineRules($dashboardApiRootUrl) {
    Write-FunctionCallLog $PSBoundParameters
    # Assigned to a variable first, not wrapped directly around the call - Get-DashboardApiResponse
    # returns via Write-ReturnValue's `return ,$x`, which emits its array as one pipeline object;
    # wrapping the call itself in @(...) collects that one emitted object into a NEW array, nesting
    # the real array one level deeper instead of flattening it (confirmed on a real host: all rules
    # collapsed onto single space-joined lines via PowerShell's member-enumeration). Assigning to a
    # plain variable first correctly unwraps it, matching the established safe pattern from
    # Certificates.ps1/NetworkInfo.ps1 in Winspect.
    $rules = Get-DashboardApiResponse $dashboardApiRootUrl "rules"
    Write-ReturnValue @($rules)
}

function Get-RulesSummary($rules) {
    Write-FunctionCallLog $PSBoundParameters
    if ($rules.Count -eq 0) {
        $output = "${INDENTATION}No rules found"
    } else {
        $blocks = @()
        foreach ($rule in $rules) {
            $lines = @()
            $lines += "$INDENTATION$($rule.RuleName)"
            $lines += "$INDENTATION${INDENTATION}RuleType$FIELD_LABEL_SEPARATOR$($rule.RuleType)"
            $lines += "$INDENTATION${INDENTATION}Version$FIELD_LABEL_SEPARATOR$($rule.Version)"
            $lines += "$INDENTATION${INDENTATION}SortOrder$FIELD_LABEL_SEPARATOR$($rule.SortOrder)"
            $lines += "$INDENTATION${INDENTATION}LastModifiedDate$FIELD_LABEL_SEPARATOR$($rule.LastModifiedDate)"
            $lines += "$INDENTATION${INDENTATION}ConnectorTypeId$FIELD_LABEL_SEPARATOR$($rule.ConnectorTypeId)"
            $lines += "$INDENTATION${INDENTATION}Definition$FIELD_LABEL_SEPARATOR"
            $definitionLines = ($rule.Definition -split "`r?`n") | ForEach-Object { "$INDENTATION$INDENTATION$INDENTATION$_" }
            $lines += $definitionLines
            $blocks += ($lines -join $LOGICAL_NEWLINE)
        }
        $output = ($blocks -join ($LOGICAL_NEWLINE + $LOGICAL_NEWLINE))
    }
    Write-ReturnValue $output
}
