BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/SagaCertificateInfo.ps1"
    . "$PSScriptRoot/../src/LingoInfo.ps1"

    function New-TestDotEnvFile($installDirPath, $lines) {
        $dockerDirPath = Join-Path $installDirPath "docker"
        New-Item -ItemType Directory -Path $dockerDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $dockerDirPath ".env") -Value $lines
    }
}

Describe "Get-LingoDataTypeAndLanguage" {
    It "reports the regular language when the configured value is a real Lingo language, not the PII marker" {
        $installDirPath = Join-Path $TestDrive "saga-install-regular"
        New-TestDotEnvFile $installDirPath @("AYFIE_LINGO_EXTRACTION_IMAGE_ID=nb")

        Get-LingoDataTypeAndLanguage $installDirPath | Should -Be "nb (regular, not PII)"
    }

    It "reports the PII language when the configured value is the PII marker" {
        $installDirPath = Join-Path $TestDrive "saga-install-pii"
        New-TestDotEnvFile $installDirPath @(
            "AYFIE_LINGO_EXTRACTION_IMAGE_ID=pii",
            "AYFIE_LINGO_EXTRACTION_PII_LANGUAGE_ID=en"
        )

        Get-LingoDataTypeAndLanguage $installDirPath | Should -Be "en (PII)"
    }

    It "reports 'Not configured' when the image ID variable isn't set at all" {
        $installDirPath = Join-Path $TestDrive "saga-install-unconfigured"
        New-TestDotEnvFile $installDirPath @("AYFIE_SAGA_BRANDING_KEY=ayfie")

        Get-LingoDataTypeAndLanguage $installDirPath | Should -Be "Not configured"
    }

    It "reports the raw value flagged as unrecognized when it's neither the PII marker nor a known language" {
        $installDirPath = Join-Path $TestDrive "saga-install-unrecognized"
        New-TestDotEnvFile $installDirPath @("AYFIE_LINGO_EXTRACTION_IMAGE_ID=xx")

        Get-LingoDataTypeAndLanguage $installDirPath | Should -Be "xx (unrecognized value)"
    }
}

Describe "Get-LingoInfo" {
    It "reads all six Lingo fields from the .env file" {
        $installDirPath = Join-Path $TestDrive "saga-install-full"
        New-TestDotEnvFile $installDirPath @(
            "AYFIE_LINGO=true",
            "AYFIE_LINGO_EXTRACTION_IMAGE_ID=nb",
            "AYFIE_LINGO_PIPELINE_POOL_SIZE=4",
            "AYFIE_LINGO_RECYCLE_ON_MEMORY_THRESHOLD_IN_MB=2048",
            "AYFIE_LINGO_RECYCLE_AFTER_RUNS=1000",
            "AYFIE_LINGO_RECYCLE_AFTER_PROCESSING_TIME_IN_SECONDS=3600"
        )

        $result = Get-LingoInfo $installDirPath

        $result.Enabled | Should -Be "true"
        $result.DataTypeAndLanguage | Should -Be "nb (regular, not PII)"
        $result.Threads | Should -Be "4"
        $result.RecycleMemoryThresholdMb | Should -Be "2048"
        $result.RecycleRuns | Should -Be "1000"
        $result.RecycleTimeSeconds | Should -Be "3600"
    }
}
