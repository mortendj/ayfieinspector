BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/SagaCertificateInfo.ps1"
    . "$PSScriptRoot/../src/PersonalAssistantInfo.ps1"

    function New-TestDotEnvFile($installDirPath) {
        $dockerDirPath = Join-Path $installDirPath "docker"
        New-Item -ItemType Directory -Path $dockerDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $dockerDirPath ".env") -Value @(
            "AYFIE_SEARCH_UI_FEATURE_CHAT=full",
            "AYFIE_CHAT_MAIN_MODEL_DEPLOYMENT=gpt-4o",
            "AYFIE_CHAT_MAIN_MODEL_DISPLAY_NAME=GPT-4o",
            "AYFIE_CHAT_HQ_MODEL_DEPLOYMENT=gpt-4o-hq",
            "AYFIE_CHAT_HQ_MODEL_DISPLAY_NAME=GPT-4o HQ",
            "AYFIE_CHAT_HQ_PLUS_MODEL_DEPLOYMENT=gpt-4o-hq-plus",
            "AYFIE_CHAT_HQ_PLUS_MODEL_DISPLAY_NAME=GPT-4o HQ+"
        )
    }
}

Describe "Get-PersonalAssistantInfo" {
    It "reads the operational mode and all six model fields from the .env file" {
        $installDirPath = Join-Path $TestDrive "saga-install-pa"
        New-TestDotEnvFile $installDirPath

        $result = Get-PersonalAssistantInfo $installDirPath

        $result.Mode | Should -Be "full"
        $result.MainModel | Should -Be "gpt-4o"
        $result.MainModelDisplayName | Should -Be "GPT-4o"
        $result.HighQualityModel | Should -Be "gpt-4o-hq"
        $result.HighQualityModelDisplayName | Should -Be "GPT-4o HQ"
        $result.HighQualityPlusModel | Should -Be "gpt-4o-hq-plus"
        $result.HighQualityPlusModelDisplayName | Should -Be "GPT-4o HQ+"
    }
}
