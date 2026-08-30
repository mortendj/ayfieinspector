function Get-ConnectorDefinitionSummary($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    # Rendered directly as raw XML text, never through anything that re-parses it as PowerShell
    # source - ConfigInspector's own version of this section had a real production crash (NGI) from
    # exactly that: wrapping already-resolved XML containing a double quote in a string and
    # Invoke-Expression-ing it broke out of the string the moment the XML itself contained one. This
    # project's report sections are plain scriptblocks whose returned text is used as-is, never
    # re-parsed, so that failure mode doesn't apply here - but the raw-text-only approach is kept
    # anyway rather than reaching for any kind of templating that could reopen it.
    $connectorsRootPath = Join-Path $installDirPath $CONNECTORS_ROOT_RELATIVE_PATH
    if (-not (Test-Path $connectorsRootPath)) {
        Write-ReturnValue "No DB connector definitions"
        return
    }
    $connectorDirs = @(Get-ChildItem -Path $connectorsRootPath -Directory)
    $blocks = @()
    foreach ($connectorDir in $connectorDirs) {
        $connectorDefFilePath = Join-Path $connectorDir.FullName $CONNECTOR_DEFINITION_RELATIVE_PATH
        if (Test-Path $connectorDefFilePath) {
            $definitionContent = Get-Content -Path $connectorDefFilePath -Raw -ErrorAction Stop
            $blocks += "Connector: $($connectorDir.Name)$LOGICAL_NEWLINE$definitionContent"
        }
    }
    if ($blocks.Count -eq 0) {
        Write-ReturnValue "No DB connector definitions"
        return
    }
    Write-ReturnValue ($blocks -join ($LOGICAL_NEWLINE + $LOGICAL_NEWLINE))
}

function Test-HasRestrictedSecuritySource($installDirPath) {
    Write-FunctionCallLog $PSBoundParameters
    # Used by Get-AuthenticationMethodSummary to say something concrete about whether a Keycloak
    # local account (or any other authenticated session) can actually see restricted data, rather
    # than just noting the account exists - confirmed on a real KTH host where a connector's
    # SecuritySources granted every document to $EVERYONE_SID, so any authenticated session saw
    # everything regardless of identity. A missing SecuritySources block counts the same as
    # everything-is-Everyone (no restriction found), not as its own separate case.
    $hasRestrictedSource = $false
    if ($installDirPath -ne "") {
        $connectorsRootPath = Join-Path $installDirPath $CONNECTORS_ROOT_RELATIVE_PATH
        if (Test-Path $connectorsRootPath) {
            $connectorDirs = @(Get-ChildItem -Path $connectorsRootPath -Directory)
            foreach ($connectorDir in $connectorDirs) {
                $connectorDefFilePath = Join-Path $connectorDir.FullName $CONNECTOR_DEFINITION_RELATIVE_PATH
                if (Test-Path $connectorDefFilePath) {
                    $definitionContent = Get-Content -Path $connectorDefFilePath -Raw
                    $sidMatches = [regex]::Matches($definitionContent, '<SID\s+value="([^"]+)"')
                    foreach ($sidMatch in $sidMatches) {
                        if ($sidMatch.Groups[1].Value -ne $EVERYONE_SID) {
                            $hasRestrictedSource = $true
                        }
                    }
                }
            }
        }
    }
    Write-ReturnValue $hasRestrictedSource
}
