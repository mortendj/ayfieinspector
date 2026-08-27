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
