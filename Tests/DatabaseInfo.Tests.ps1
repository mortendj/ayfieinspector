BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/SagaCertificateInfo.ps1"
    . "$PSScriptRoot/../src/DatabaseInfo.ps1"

    function New-TestDotEnvFile($installDirPath) {
        $dockerDirPath = Join-Path $installDirPath "docker"
        New-Item -ItemType Directory -Path $dockerDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $dockerDirPath ".env") -Value @(
            "AYFIE_SAGA_DATABASE_TYPE=MSSQL",
            "AYFIE_SAGA_DATABASE_NAME=Locator",
            "AYFIE_SAGA_DATABASE_USER_NAME=postgres",
            "AYFIE_SAGA_DATABASE_SERVER=dbserver.example.com",
            "AYFIE_SAGA_DATABASE_PORT=1433",
            "AYFIE_SAGA_AD_AAD_SYNC=true"
        )
    }
}

Describe "Get-DatabaseInfo" {
    It "reads type, name, user, server, and port from the .env file" {
        $installDirPath = Join-Path $TestDrive "saga-install-db"
        New-TestDotEnvFile $installDirPath

        $result = Get-DatabaseInfo $installDirPath

        $result.Type | Should -Be "MSSQL"
        $result.Name | Should -Be "Locator"
        $result.User | Should -Be "postgres"
        $result.Server | Should -Be "dbserver.example.com"
        $result.Port | Should -Be "1433"
    }
}

Describe "Get-AdAndAzureAdSync" {
    It "reads the AD/Azure AD syncing flag from the .env file" {
        $installDirPath = Join-Path $TestDrive "saga-install-sync"
        New-TestDotEnvFile $installDirPath

        Get-AdAndAzureAdSync $installDirPath | Should -Be "true"
    }
}
