BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/SagaCertificateInfo.ps1"

    function New-DockerInspectLines($mountSources) {
        # Mimics real `docker inspect` output: a one-element JSON array, pretty-printed across
        # multiple lines, returned as an array of lines - exactly what Invoke-ExternalCommand's
        # Get-Content-based capture hands back, not a single JSON string.
        $mounts = @($mountSources | ForEach-Object { [pscustomobject]@{ Source = $_ } })
        $containerConfig = @([pscustomobject]@{ Mounts = $mounts })
        $json = $containerConfig | ConvertTo-Json -Depth 5
        return ,@($json -split "`n")
    }
}

Describe "Get-SagaInstallDirPath" {
    It "derives the install directory as the common prefix of two bind mount sources" {
        Mock Invoke-ExternalCommand {
            New-DockerInspectLines @("C:\Saga\docker\volumes\a", "C:\Saga\docker\volumes\b")
        }

        Get-SagaInstallDirPath | Should -Be "C:\Saga\docker\volumes\"
    }

    It "returns null when the container has fewer than two mounts to compare" {
        Mock Invoke-ExternalCommand { New-DockerInspectLines @("C:\Saga\docker\volumes\a") }

        Get-SagaInstallDirPath | Should -BeNullOrEmpty
    }

    It "does not hang when both mount sources are identical" {
        Mock Invoke-ExternalCommand {
            New-DockerInspectLines @("C:\Saga\docker\volumes\a", "C:\Saga\docker\volumes\a")
        }

        Get-SagaInstallDirPath | Should -Be "C:\Saga\docker\volumes\a"
    }

    It "never passes an argument containing whitespace to Invoke-ExternalCommand" {
        # Regression test for a real bug found on a production host: Invoke-ExternalCommand passes
        # each argument straight to Start-Process -ArgumentList, which splits on internal whitespace
        # rather than quoting it - a template argument like "{{json .}}" arrived at docker broken
        # into two garbled arguments, and docker rejected it as "template parsing error: template:
        # :1: unclosed action". No argument here may contain a space.
        Mock Invoke-ExternalCommand {
            param($commandName, $commandArgs)
            foreach ($arg in $commandArgs) {
                $arg | Should -Not -Match ' '
            }
            New-DockerInspectLines @("C:\Saga\docker\volumes\a", "C:\Saga\docker\volumes\b")
        }

        Get-SagaInstallDirPath | Out-Null
    }
}

Describe "Get-DotEnvValue" {
    It "reads the value for a given key from a .env-style file" {
        $dotEnvFilePath = Join-Path $TestDrive "test.env"
        Set-Content -Path $dotEnvFilePath -Value @("SOME_OTHER_KEY=ignored", "AYFIE_SAGA_GATEWAY_CERTIFICATE_NAME=gateway")

        Get-DotEnvValue $dotEnvFilePath "AYFIE_SAGA_GATEWAY_CERTIFICATE_NAME" | Should -Be "gateway"
    }

    It "returns null when the key is not present" {
        $dotEnvFilePath = Join-Path $TestDrive "test2.env"
        Set-Content -Path $dotEnvFilePath -Value @("SOME_OTHER_KEY=ignored")

        Get-DotEnvValue $dotEnvFilePath "AYFIE_SAGA_GATEWAY_CERTIFICATE_NAME" | Should -BeNullOrEmpty
    }
}

Describe "Get-ResolvedGmsaAccountName" {
    It "returns the explicitly passed account name unchanged, without touching the install dir" {
        Get-ResolvedGmsaAccountName "domain\explicit-account" "C:\Saga" | Should -Be "domain\explicit-account"
    }

    It "auto-discovers the account name from docker/.env when none was explicitly passed" {
        $installDirPath = Join-Path $TestDrive "auto-discover"
        New-Item -ItemType Directory -Path (Join-Path $installDirPath "docker") -Force | Out-Null
        Set-Content -Path (Join-Path $installDirPath "docker/.env") -Value @("AYFIE_SAGA_AD_SERVICE_ACCOUNT=SWECO\msvc_swecosok$")

        Get-ResolvedGmsaAccountName "" $installDirPath | Should -Be "SWECO\msvc_swecosok$"
    }

    It "returns an empty string when nothing was passed and there's no install dir to auto-discover from" {
        Get-ResolvedGmsaAccountName "" "" | Should -Be ""
    }

    It "returns an empty string when auto-discovery finds no matching key" {
        $installDirPath = Join-Path $TestDrive "no-key"
        New-Item -ItemType Directory -Path (Join-Path $installDirPath "docker") -Force | Out-Null
        Set-Content -Path (Join-Path $installDirPath "docker/.env") -Value @("SOME_OTHER_KEY=ignored")

        Get-ResolvedGmsaAccountName "" $installDirPath | Should -Be ""
    }
}

Describe "Get-CertificateAuthority" {
    It "returns the certificate's Issuer property" {
        $certificate = [pscustomobject]@{ Issuer = "CN=DigiCert Global CA" }

        Get-CertificateAuthority $certificate | Should -Be "CN=DigiCert Global CA"
    }
}

Describe "Get-CertificateSubjectAlternativeNames" {
    It "joins every DNS name in the certificate's DnsNameList" {
        $certificate = [pscustomobject]@{
            DnsNameList = @([pscustomobject]@{ Unicode = "search.example.com" }, [pscustomobject]@{ Unicode = "search-alt.example.com" })
        }

        Get-CertificateSubjectAlternativeNames $certificate | Should -Be "search.example.com, search-alt.example.com"
    }

    It "returns an empty string, not an error, when there are no subject alternative names" {
        $certificate = [pscustomobject]@{ DnsNameList = @() }

        Get-CertificateSubjectAlternativeNames $certificate | Should -Be ""
    }
}

Describe "Get-CertificateKeyEncryptionStatus" {
    It "reports 'Encrypted' for a PEM key file with an encrypted private key header" {
        $keyFilePath = Join-Path $TestDrive "encrypted.key"
        Set-Content -Path $keyFilePath -Value "-----BEGIN ENCRYPTED PRIVATE KEY-----`nabc123`n-----END ENCRYPTED PRIVATE KEY-----"

        Get-CertificateKeyEncryptionStatus $keyFilePath | Should -Be "Encrypted"
    }

    It "reports 'Unencrypted' for a PEM key file with a plain private key header" {
        $keyFilePath = Join-Path $TestDrive "unencrypted.key"
        Set-Content -Path $keyFilePath -Value "-----BEGIN PRIVATE KEY-----`nabc123`n-----END PRIVATE KEY-----"

        Get-CertificateKeyEncryptionStatus $keyFilePath | Should -Be "Unencrypted"
    }

    It "reports the RSA case separately, since encryption status isn't easily determined for it" {
        $keyFilePath = Join-Path $TestDrive "rsa.key"
        Set-Content -Path $keyFilePath -Value "-----BEGIN RSA PRIVATE KEY-----`nabc123`n-----END RSA PRIVATE KEY-----"

        Get-CertificateKeyEncryptionStatus $keyFilePath | Should -Be "RSA key (encryption status not easily determined)"
    }

    It "derives the .key file path from the certificate file path, not a path passed in directly" {
        $certificateFilePath = Join-Path $TestDrive "gateway.crt"
        Set-Content -Path (Join-Path $TestDrive "gateway.key") -Value "-----BEGIN PRIVATE KEY-----`nabc123`n-----END PRIVATE KEY-----"

        Get-CertificateKeyEncryptionStatus $certificateFilePath | Should -Be "Unencrypted"
    }
}

Describe "Get-SagaGatewayCertificateInfo" {
    It "returns the file override as-is and no hostname at all, without touching docker" {
        Mock Get-SagaInstallDirPath { throw "should not be called" }

        $result = Get-SagaGatewayCertificateInfo "C:\explicit\gateway.crt"

        $result.CertificateFilePath | Should -Be "C:\explicit\gateway.crt"
        $result.CertificateHostname | Should -Be ""
        $result.InstallDirPath | Should -Be ""
    }

    It "auto-discovers both the certificate path and the gateway hostname from the install directory and .env when no override is given" {
        Mock Get-SagaInstallDirPath { "C:\Saga\" }
        Mock Get-DotEnvValue {
            param($dotEnvFilePath, $key)
            if ($key -eq $GATEWAY_CERTIFICATE_NAME_KEY) { "gateway" }
            elseif ($key -eq $GATEWAY_HOSTNAME_KEY) { "search.customer.example.com" }
        }

        $result = Get-SagaGatewayCertificateInfo ""

        $result.CertificateFilePath | Should -Be "C:\Saga\volumes\Traefik\certs\gateway.crt"
        $result.CertificateHostname | Should -Be "search.customer.example.com"
        $result.InstallDirPath | Should -Be "C:\Saga\"
    }
}
