BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/ConnectorDefinitionInfo.ps1"
    . "$PSScriptRoot/../src/AuthenticationInfo.ps1"
}

Describe "Get-ProviderCount" {
    It "parses the bare count from psql's -t -A (tuples-only, unaligned) output" {
        Mock Invoke-ExternalCommand { @("1") }

        Get-ProviderCount "public.identity_provider" "'saga'" | Should -Be 1
    }

    It "tolerates a trailing blank line in the psql output" {
        Mock Invoke-ExternalCommand { @("0", "") }

        Get-ProviderCount "public.identity_provider" "'saga'" | Should -Be 0
    }

    It "never passes an argument containing whitespace to Invoke-ExternalCommand's SQL argument only if unquoted - this call relies on Invoke-ExternalCommand's own quoting, not on avoiding spaces" {
        # Unlike SagaCertificateInfo.ps1's docker inspect call (which avoids whitespace arguments
        # entirely), the SQL query here genuinely can't avoid spaces - this call only works because
        # Invoke-ExternalCommand itself now quotes whitespace-containing arguments before passing
        # them to Start-Process (see Winspect's Utilities.Tests.ps1 for the regression test of that
        # fix). This test just confirms the SQL argument actually reaches Invoke-ExternalCommand
        # as one single argument, not already pre-split by this function.
        $script:capturedArgs = $null
        Mock Invoke-ExternalCommand {
            param($commandName, $commandArgs)
            $script:capturedArgs = $commandArgs
            @("1")
        }

        Get-ProviderCount "public.identity_provider" "SELECT id FROM public.realm WHERE name = 'saga'" | Out-Null

        ($script:capturedArgs | Where-Object { $_ -match "SELECT" }).Count | Should -Be 1
    }

    It "includes the additional WHERE clause in the query when one is given" {
        $script:capturedArgs = $null
        Mock Invoke-ExternalCommand {
            param($commandName, $commandArgs)
            $script:capturedArgs = $commandArgs
            @("1")
        }

        Get-ProviderCount "public.component" "'realm-id'" "provider_type = 'org.keycloak.storage.UserStorageProvider'" | Out-Null

        ($script:capturedArgs -join " ") | Should -Match "AND provider_type = 'org\.keycloak\.storage\.UserStorageProvider'"
    }
}

Describe "Get-UserFederationProviderCount" {
    It "queries public.component filtered to UserStorageProvider rows, not the legacy user_federation_provider table" {
        # Regression test for a real finding on a customer host: modern Keycloak stores LDAP/AD
        # federation as a row in the generic public.component table (provider_type =
        # org.keycloak.storage.UserStorageProvider), not in the older dedicated
        # public.user_federation_provider table - confirmed empty on a host that has LDAP genuinely
        # configured, while public.component correctly had exactly one matching row there.
        $script:capturedArgs = $null
        Mock Invoke-ExternalCommand {
            param($commandName, $commandArgs)
            $script:capturedArgs = $commandArgs
            @("1")
        }

        Get-UserFederationProviderCount | Should -Be 1

        $capturedSql = @($script:capturedArgs | Where-Object { $_ -match "SELECT" })[0]
        $capturedSql | Should -Match "FROM public\.component "
        $capturedSql | Should -Match "provider_type = 'org\.keycloak\.storage\.UserStorageProvider'"
        $capturedSql | Should -Not -Match "user_federation_provider"
    }
}

Describe "Get-LocalUserAccountCount" {
    It "queries public.user_entity excluding federated, service-account, and the saga_admin bootstrap users" {
        # Regression test: saga_admin exists in every Saga realm regardless of whether real
        # application authentication is configured (it's Keycloak's own console-admin bootstrap
        # account, provisioned by Saga's deployment itself - KEYCLOAK_USER=saga_admin in every
        # install's .env) - counting it toward "local accounts that might explain application
        # access" is misleading, confirmed by Morten on a real KTH host.
        $script:capturedArgs = $null
        Mock Invoke-ExternalCommand {
            param($commandName, $commandArgs)
            $script:capturedArgs = $commandArgs
            @("1")
        }

        Get-LocalUserAccountCount | Should -Be 1

        $capturedSql = @($script:capturedArgs | Where-Object { $_ -match "SELECT" })[0]
        $capturedSql | Should -Match "FROM public\.user_entity "
        $capturedSql | Should -Match "federation_link IS NULL"
        $capturedSql | Should -Match "service_account_client_link IS NULL"
        $capturedSql | Should -Match "username != 'saga_admin'"
    }
}

Describe "Get-AuthenticationMethodSummary" {
    It "reports 'Not configured' when there are zero providers of either kind and no local accounts" {
        # Regression case: real production hosts have legitimately had zero providers configured
        # (an in-progress deployment) - this must not throw or look like an error.
        Mock Get-IdentityProviderCount { 0 }
        Mock Get-UserFederationProviderCount { 0 }
        Mock Get-LocalUserAccountCount { 0 }

        Get-AuthenticationMethodSummary "" | Should -Be "Not configured (0 identity providers, 0 user federation providers)"
    }

    It "states plainly when local accounts exist but no restricted security source was found" {
        # Regression case: a real KTH host had zero identity providers and zero user federation
        # providers configured, yet API access kept working via a locally-created Keycloak account
        # (confirmed via its "source: local" attribute in the admin console) - this section used to
        # report "Not configured" with nothing explaining why access still worked. An earlier version
        # of this fix worded it as vague reassurance ("may be used for direct authentication") or as
        # unresolved homework ("verify...") - Morten wanted a concrete answer instead: whether a
        # connector's security sources actually restrict access per-user, or grant it to everyone.
        Mock Get-IdentityProviderCount { 0 }
        Mock Get-UserFederationProviderCount { 0 }
        Mock Get-LocalUserAccountCount { 1 }
        Mock Test-HasRestrictedSecuritySource { $false }

        $result = Get-AuthenticationMethodSummary "C:\Saga"

        $result | Should -Be "Not configured (0 identity providers, 0 user federation providers). 1 non-admin local Keycloak account(s) exist. All connector security sources are 'Everyone' (S-1-1-0) - no per-user document restriction found."
    }

    It "states plainly when local accounts exist and a restricted security source was found" {
        Mock Get-IdentityProviderCount { 0 }
        Mock Get-UserFederationProviderCount { 0 }
        Mock Get-LocalUserAccountCount { 1 }
        Mock Test-HasRestrictedSecuritySource { $true }

        $result = Get-AuthenticationMethodSummary "C:\Saga"

        $result | Should -Be "Not configured (0 identity providers, 0 user federation providers). 1 non-admin local Keycloak account(s) exist. Connector security sources include SIDs other than 'Everyone' - per-user document restriction may apply."
    }

    It "reports 'Entra ID' when there is exactly one identity provider and no user federation" {
        # Regression case: confirmed on a real production host.
        Mock Get-IdentityProviderCount { 1 }
        Mock Get-UserFederationProviderCount { 0 }

        Get-AuthenticationMethodSummary "" | Should -Be "Entra ID"
    }

    It "reports 'Active Directory' when there is exactly one user federation provider and no identity provider" {
        Mock Get-IdentityProviderCount { 0 }
        Mock Get-UserFederationProviderCount { 1 }

        Get-AuthenticationMethodSummary "" | Should -Be "Active Directory"
    }

    It "flags an ambiguous configuration rather than silently picking one when both are set" {
        Mock Get-IdentityProviderCount { 1 }
        Mock Get-UserFederationProviderCount { 1 }

        Get-AuthenticationMethodSummary "" | Should -Match "^Ambiguous"
    }
}
