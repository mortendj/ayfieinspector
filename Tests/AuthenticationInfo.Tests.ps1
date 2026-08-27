BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
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

Describe "Get-AuthenticationMethodSummary" {
    It "reports 'Not configured' when there are zero providers of either kind" {
        # Regression case: real production hosts have legitimately had zero providers configured
        # (an in-progress deployment) - this must not throw or look like an error.
        Mock Get-IdentityProviderCount { 0 }
        Mock Get-UserFederationProviderCount { 0 }

        Get-AuthenticationMethodSummary | Should -Be "Not configured (0 identity providers, 0 user federation providers)"
    }

    It "reports 'Entra ID' when there is exactly one identity provider and no user federation" {
        # Regression case: confirmed on a real production host.
        Mock Get-IdentityProviderCount { 1 }
        Mock Get-UserFederationProviderCount { 0 }

        Get-AuthenticationMethodSummary | Should -Be "Entra ID"
    }

    It "reports 'Active Directory' when there is exactly one user federation provider and no identity provider" {
        Mock Get-IdentityProviderCount { 0 }
        Mock Get-UserFederationProviderCount { 1 }

        Get-AuthenticationMethodSummary | Should -Be "Active Directory"
    }

    It "flags an ambiguous configuration rather than silently picking one when both are set" {
        Mock Get-IdentityProviderCount { 1 }
        Mock Get-UserFederationProviderCount { 1 }

        Get-AuthenticationMethodSummary | Should -Match "^Ambiguous"
    }
}
