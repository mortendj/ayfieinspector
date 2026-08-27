function Get-ProviderCount($providerTable, $realmIdExpression) {
    Write-FunctionCallLog $PSBoundParameters
    $sql = "SELECT COUNT(*) FROM $providerTable WHERE realm_id = ($realmIdExpression);"
    # -t (tuples only) -A (unaligned) makes psql print just the bare count on its own line, rather
    # than a padded ASCII table whose header/separator/row positions would otherwise have to be
    # assumed - more robust than depending on a specific line index in psql's default output.
    $outputLines = Invoke-ExternalCommand "docker" @("exec", $AUTHORITY_DB_CONTAINER_NAME, "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-c", $sql)
    $countLine = @($outputLines | Where-Object { $_.Trim() -ne "" })[0]
    Write-ReturnValue ([int]$countLine.Trim())
}

function Get-IdentityProviderCount() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue (Get-ProviderCount $IDENTITY_PROVIDER_TABLE "SELECT id FROM public.realm WHERE name = '$SAGA_REALM_NAME'")
}

function Get-UserFederationProviderCount() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue (Get-ProviderCount $USER_FEDERATION_PROVIDER_TABLE "'$SAGA_REALM_NAME'")
}

function Get-AuthenticationMethodSummary() {
    Write-FunctionCallLog $PSBoundParameters
    $identityProviderCount = Get-IdentityProviderCount
    $userFederationCount = Get-UserFederationProviderCount
    $totalProviders = $identityProviderCount + $userFederationCount

    if ($totalProviders -eq 0) {
        # A legitimate "nothing configured yet" state, not necessarily an error - confirmed on real
        # production hosts, where nothing has been set up yet mid-deployment. Reported plainly
        # rather than as an error, since treating it as one would be misleading for what's often
        # just an in-progress installation.
        $summary = "Not configured (0 identity providers, 0 user federation providers)"
    } elseif ($totalProviders -eq 1) {
        if ($identityProviderCount -eq 1) {
            $summary = $IDENTITY_PROVIDER_AUTH_METHOD_NAME
        } else {
            $summary = $USER_FEDERATION_AUTH_METHOD_NAME
        }
    } else {
        $summary = "Ambiguous ($identityProviderCount identity provider(s), $userFederationCount user federation provider(s) - expected exactly 1 total)"
    }
    Write-ReturnValue $summary
}
