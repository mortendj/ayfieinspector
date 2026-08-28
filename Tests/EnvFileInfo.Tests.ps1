BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/EnvFileInfo.ps1"
}

Describe "Get-EnvFileKeyValuePairs" {
    It "parses key=value lines, skipping comments and blank lines" {
        $envFilePath = Join-Path $TestDrive "custom.env"
        Set-Content -Path $envFilePath -Value @(
            "# a comment line",
            "",
            "AYFIE_SAGA_BRANDING_KEY=custom",
            "AYFIE_SAGA_HOST_IP=10.0.0.4"
        )

        $result = Get-EnvFileKeyValuePairs $envFilePath

        $result["AYFIE_SAGA_BRANDING_KEY"] | Should -Be "custom"
        $result["AYFIE_SAGA_HOST_IP"] | Should -Be "10.0.0.4"
        $result.Keys.Count | Should -Be 2
    }

    It "splits only on the first '=', so values containing '=' survive intact" {
        $envFilePath = Join-Path $TestDrive "custom-with-equals.env"
        Set-Content -Path $envFilePath -Value "SOLR_JAVA_MEM=-Xms8g -Xmx8g"

        (Get-EnvFileKeyValuePairs $envFilePath)["SOLR_JAVA_MEM"] | Should -Be "-Xms8g -Xmx8g"
    }
}

Describe "Remove-SensitiveDotEnvKeys" {
    It "drops keys matching a sensitive token from the dictionary, keeping the rest intact" {
        $keyValuePairs = [ordered]@{
            AYFIE_SAGA_DATABASE_PASSWORD = "hunter2"
            AYFIE_SAGA_BRANDING_KEY = "custom"
        }

        $result = Remove-SensitiveDotEnvKeys $keyValuePairs @("PASSWORD")

        $result.Contains("AYFIE_SAGA_DATABASE_PASSWORD") | Should -BeFalse
        $result["AYFIE_SAGA_BRANDING_KEY"] | Should -Be "custom"
    }
}

Describe "Get-SecurityClearedEnvFileContent" {
    It "drops keys matching a sensitive token entirely, rather than masking the value" {
        $envFilePath = Join-Path $TestDrive "with-secrets.env"
        Set-Content -Path $envFilePath -Value @(
            "AYFIE_SAGA_DATABASE_PASSWORD=hunter2",
            "AYFIE_SAGA_API_TOKEN=abc123",
            "AYFIE_SAGA_BRANDING_KEY=custom"
        )

        $result = Get-SecurityClearedEnvFileContent $envFilePath @("PASSWORD", "API_TOKEN")

        $result | Should -Not -Match "hunter2"
        $result | Should -Not -Match "abc123"
        $result | Should -Not -Match "PASSWORD"
        $result | Should -Not -Match "API_TOKEN"
        $result | Should -Match "AYFIE_SAGA_BRANDING_KEY=custom"
    }

    It "returns an empty string when every key is sensitive" {
        $envFilePath = Join-Path $TestDrive "all-secrets.env"
        Set-Content -Path $envFilePath -Value "AYFIE_SAGA_SECRET=xyz"

        Get-SecurityClearedEnvFileContent $envFilePath @("SECRET") | Should -Be ""
    }
}

Describe "Get-CustomEnvFileContent" {
    It "redacts sensitive keys from the resolved custom.env under the install directory" {
        $installDirPath = Join-Path $TestDrive "saga-install"
        $dockerDirPath = Join-Path $installDirPath "docker"
        New-Item -ItemType Directory -Path $dockerDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $dockerDirPath "custom.env") -Value @(
            "AYFIE_SAGA_API_TOKEN=abc123",
            "AYFIE_SAGA_BRANDING_KEY=custom"
        )

        $result = Get-CustomEnvFileContent $installDirPath

        $result | Should -Not -Match "abc123"
        $result | Should -Match "AYFIE_SAGA_BRANDING_KEY=custom"
    }

    It "reports that no customizations exist when custom.env isn't present, rather than throwing" {
        $installDirPath = Join-Path $TestDrive "saga-install-no-custom-env"
        New-Item -ItemType Directory -Path (Join-Path $installDirPath "docker") -Force | Out-Null

        Get-CustomEnvFileContent $installDirPath | Should -Match "Not present"
    }
}
