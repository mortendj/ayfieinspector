BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/DockerInfo.ps1"
}

Describe "Get-RunningContainerNames" {
    It "returns the container names from 'docker ps --format {{.Names}}'" {
        Mock Invoke-ExternalCommand {
            @("ayfie-saga-authority-db", "ayfie-connector-fileserver")
        } -ParameterFilter { $commandName -eq "docker" -and $commandArgs -join "," -eq "ps,--format,{{.Names}}" }

        $result = Get-RunningContainerNames

        $result | Should -Contain "ayfie-connector-fileserver"
    }
}

Describe "Get-DockerImagesOfRunningContainers" {
    It "joins the image list into newline-separated text" {
        Mock Invoke-ExternalCommand { @("ayfiehub/locator:7.3.1", "ayfiehub/solr:7.4.0") }

        $result = Get-DockerImagesOfRunningContainers

        $result | Should -Match "ayfiehub/locator:7\.3\.1"
        $result | Should -Match "ayfiehub/solr:7\.4\.0"
    }
}

Describe "Get-RunningConnectorNames" {
    It "extracts just the connector name from ayfie-connector-<name> container names" {
        Mock Get-RunningContainerNames { @("ayfie-saga-authority-db", "ayfie-connector-fileserver", "ayfie-connector-exchange") }

        $result = Get-RunningConnectorNames

        $result | Should -Match "fileserver"
        $result | Should -Match "exchange"
        $result | Should -Not -Match "authority-db"
    }

    It "reports 'No containers' when nothing matches, rather than an empty string" {
        Mock Get-RunningContainerNames { @("ayfie-saga-authority-db") }

        Get-RunningConnectorNames | Should -Be "No containers"
    }
}
