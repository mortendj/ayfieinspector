BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../../Winspect/src/ReportFormatting.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/EnvFileInfo.ps1"
    . "$PSScriptRoot/../src/EnvConfigDiffInfo.ps1"

    Initialize-OutputFormatLayout "text"

    # Builds a fake Saga install directory: a real docker/.env (and optional custom.env) plus a
    # real Ayfie.Saga.zip containing Saga/docker/.env as the pristine reference - exercising the
    # real Expand-Archive call rather than mocking it, the same way EnvFileInfo.Tests.ps1 exercises
    # real file reads instead of mocking Get-Content.
    function New-TestSagaInstall($installDirPath, $referenceEnvLines, $actualEnvLines, $customEnvLines = $null) {
        $dockerDirPath = Join-Path $installDirPath "docker"
        New-Item -ItemType Directory -Path $dockerDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $dockerDirPath ".env") -Value $actualEnvLines
        if ($null -ne $customEnvLines) {
            Set-Content -Path (Join-Path $dockerDirPath "custom.env") -Value $customEnvLines
        }

        $stagingDirPath = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        $stagingDockerDirPath = Join-Path $stagingDirPath "Saga\docker"
        New-Item -ItemType Directory -Path $stagingDockerDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $stagingDockerDirPath ".env") -Value $referenceEnvLines
        Compress-Archive -Path (Join-Path $stagingDirPath "Saga") -DestinationPath (Join-Path $installDirPath "Ayfie.Saga.zip") -Force
    }
}

Describe "Get-ReferenceEnvFileKeyValuePairs" {
    It "extracts Saga/docker/.env from Ayfie.Saga.zip at the install root" {
        $installDirPath = Join-Path $TestDrive "saga-install-ref"
        New-TestSagaInstall $installDirPath @("AYFIE_SAGA_BRANDING_KEY=ayfie") @("AYFIE_SAGA_BRANDING_KEY=custom")

        $result = Get-ReferenceEnvFileKeyValuePairs $installDirPath

        $result["AYFIE_SAGA_BRANDING_KEY"] | Should -Be "ayfie"
    }
}

Describe "Get-DecoratedEnvKeyList" {
    It "reports 'None' for an empty key list" {
        Get-DecoratedEnvKeyList @() @{} $false | Should -Be "None"
    }

    It "reports a single key inline with its value, without a bulleted line" {
        Get-DecoratedEnvKeyList @("AYFIE_ADDED_VAR") @{ AYFIE_ADDED_VAR = "value" } $false | Should -Be "AYFIE_ADDED_VAR (value)"
    }

    It "skips the value when skipValue is set, e.g. for a removed key with no current value" {
        Get-DecoratedEnvKeyList @("AYFIE_REMOVED_VAR") @{} $true | Should -Be "AYFIE_REMOVED_VAR"
    }

    It "renders a bulleted multi-line block once there's more than one key" {
        $result = Get-DecoratedEnvKeyList @("VAR_A", "VAR_B") @{ VAR_A = "1"; VAR_B = "2" } $false

        $result | Should -Match "VAR_A \(1\)"
        $result | Should -Match "VAR_B \(2\)"
    }
}

Describe "Get-EnvConfigDiff" {
    It "reports a removed variable that's in the reference but no longer in the actual .env" {
        $installDirPath = Join-Path $TestDrive "saga-install-removed"
        New-TestSagaInstall $installDirPath @("AYFIE_REMOVED_VAR=x", "AYFIE_SAGA_BRANDING_KEY=ayfie") @("AYFIE_SAGA_BRANDING_KEY=ayfie")

        $result = Get-EnvConfigDiff $installDirPath

        $result.Removed | Should -Be "AYFIE_REMOVED_VAR"
        $result.Added | Should -Be "None"
        $result.Modified | Should -Be "None"
    }

    It "reports an added variable that's in the actual .env but not the reference or custom.env" {
        $installDirPath = Join-Path $TestDrive "saga-install-added"
        New-TestSagaInstall $installDirPath @("AYFIE_SAGA_BRANDING_KEY=ayfie") @("AYFIE_SAGA_BRANDING_KEY=ayfie", "AYFIE_ADDED_VAR=new")

        $result = Get-EnvConfigDiff $installDirPath

        $result.Added | Should -Be "AYFIE_ADDED_VAR (new)"
    }

    It "reports a modified variable whose value differs from the reference" {
        $installDirPath = Join-Path $TestDrive "saga-install-modified"
        New-TestSagaInstall $installDirPath @("AYFIE_SAGA_BRANDING_KEY=ayfie") @("AYFIE_SAGA_BRANDING_KEY=custom")

        $result = Get-EnvConfigDiff $installDirPath

        $result.Modified | Should -Be "AYFIE_SAGA_BRANDING_KEY (custom)"
    }

    It "excludes a variable from added/modified once it's accounted for by custom.env" {
        $installDirPath = Join-Path $TestDrive "saga-install-custom-override"
        New-TestSagaInstall $installDirPath `
            @("AYFIE_SAGA_BRANDING_KEY=ayfie") `
            @("AYFIE_SAGA_BRANDING_KEY=custom", "AYFIE_CUSTOM_ONLY_VAR=y") `
            @("AYFIE_SAGA_BRANDING_KEY=custom", "AYFIE_CUSTOM_ONLY_VAR=y")

        $result = Get-EnvConfigDiff $installDirPath

        $result.Added | Should -Be "None"
        $result.Modified | Should -Be "None"
    }

    It "never reports COMPOSE_FILE as modified, since Saga's own tooling rewrites it legitimately" {
        $installDirPath = Join-Path $TestDrive "saga-install-compose-file"
        New-TestSagaInstall $installDirPath @("COMPOSE_FILE=docker-compose.yml") @("COMPOSE_FILE=docker-compose.yml:docker-compose.chat.yml")

        $result = Get-EnvConfigDiff $installDirPath

        $result.Modified | Should -Be "None"
    }

    It "drops sensitive keys entirely from consideration on both sides of the diff" {
        $installDirPath = Join-Path $TestDrive "saga-install-sensitive"
        New-TestSagaInstall $installDirPath @("AYFIE_SAGA_DATABASE_PASSWORD=old") @("AYFIE_SAGA_DATABASE_PASSWORD=new")

        $result = Get-EnvConfigDiff $installDirPath

        $result.Modified | Should -Be "None"
    }
}
