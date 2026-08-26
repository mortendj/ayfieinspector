BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/SagaCertificateInfo.ps1"
}

Describe "Get-SagaInstallDirPath" {
    It "derives the install directory as the common prefix of two bind mount sources" {
        Mock Invoke-ExternalCommand {
            '{"Mounts":[{"Source":"C:\\Saga\\docker\\volumes\\a"},{"Source":"C:\\Saga\\docker\\volumes\\b"}]}'
        }

        Get-SagaInstallDirPath | Should -Be "C:\Saga\docker\volumes\"
    }

    It "returns null when the container has fewer than two mounts to compare" {
        Mock Invoke-ExternalCommand { '{"Mounts":[{"Source":"C:\\Saga\\docker\\volumes\\a"}]}' }

        Get-SagaInstallDirPath | Should -BeNullOrEmpty
    }

    It "does not hang when both mount sources are identical" {
        Mock Invoke-ExternalCommand {
            '{"Mounts":[{"Source":"C:\\Saga\\docker\\volumes\\a"},{"Source":"C:\\Saga\\docker\\volumes\\a"}]}'
        }

        Get-SagaInstallDirPath | Should -Be "C:\Saga\docker\volumes\a"
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

Describe "Get-SagaGatewayCertificateFilePath" {
    It "returns the override as-is when one is given, without touching docker at all" {
        Mock Get-SagaInstallDirPath { throw "should not be called" }

        Get-SagaGatewayCertificateFilePath "C:\explicit\gateway.crt" | Should -Be "C:\explicit\gateway.crt"
    }

    It "auto-discovers the certificate path from the install directory and .env when no override is given" {
        Mock Get-SagaInstallDirPath { "C:\Saga\" }
        Mock Get-DotEnvValue { "gateway" }

        Get-SagaGatewayCertificateFilePath "" | Should -Be "C:\Saga\volumes\Traefik\certs\gateway.crt"
    }
}
