function Get-ProviderCount($providerTable, $realmIdExpression, $additionalWhereClause = "") {
    Write-FunctionCallLog $PSBoundParameters
    $sql = "SELECT COUNT(*) FROM $providerTable WHERE realm_id = ($realmIdExpression)"
    if ($additionalWhereClause -ne "") {
        $sql += " AND $additionalWhereClause"
    }
    $sql += ";"
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
    Write-ReturnValue (Get-ProviderCount $COMPONENT_TABLE "SELECT id FROM public.realm WHERE name = '$SAGA_REALM_NAME'" "provider_type = '$USER_STORAGE_PROVIDER_TYPE'")
}

function Get-LocalUserAccountCount() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue (Get-ProviderCount $USER_ENTITY_TABLE "SELECT id FROM public.realm WHERE name = '$SAGA_REALM_NAME'" $LOCAL_USER_WHERE_CLAUSE)
}

function Get-AuthenticationMethodSummary($installDirPath) {
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
        # Neither supported mechanism is configured, but that doesn't mean nobody can authenticate -
        # see the $USER_ENTITY_TABLE comment in Constants.ps1. Confirmed on a real KTH host: API
        # access kept working via a local Keycloak account while this section showed zero of the two
        # supported mechanisms. Whether that matters depends on whether the account can actually see
        # restricted data - Test-HasRestrictedSecuritySource answers that concretely instead of just
        # flagging the account and leaving it as homework.
        $localUserCount = Get-LocalUserAccountCount
        if ($localUserCount -gt 0) {
            $summary += ". $localUserCount non-admin local Keycloak account(s) exist."
            if (Test-HasRestrictedSecuritySource $installDirPath) {
                $summary += " Connector security sources include SIDs other than 'Everyone' - per-user document restriction may apply."
            } else {
                $summary += " All connector security sources are 'Everyone' ($EVERYONE_SID) - no per-user document restriction found."
            }
        }
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
