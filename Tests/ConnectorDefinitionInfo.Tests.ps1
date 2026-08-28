BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../../Winspect/src/ReportFormatting.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/ConnectorDefinitionInfo.ps1"

    Initialize-OutputFormatLayout "text"

    function New-TestConnectorDefinition($installDirPath, $connectorName, $xmlContent) {
        $connectorDefDirPath = Join-Path $installDirPath "volumes\Connector\$connectorName\ConnectorDefinition"
        New-Item -ItemType Directory -Path $connectorDefDirPath -Force | Out-Null
        Set-Content -Path (Join-Path $connectorDefDirPath "ConnectorDefinition.xml") -Value $xmlContent
    }
}

Describe "Get-ConnectorDefinitionSummary" {
    It "reports 'No DB connector definitions' when the connectors root directory doesn't exist at all" {
        $installDirPath = Join-Path $TestDrive "saga-install-no-connectors-dir"
        New-Item -ItemType Directory -Path $installDirPath -Force | Out-Null

        Get-ConnectorDefinitionSummary $installDirPath | Should -Be "No DB connector definitions"
    }

    It "reports 'No DB connector definitions' when the connectors root exists but no connector has a definition file" {
        $installDirPath = Join-Path $TestDrive "saga-install-no-definitions"
        New-Item -ItemType Directory -Path (Join-Path $installDirPath "volumes\Connector\fileserver") -Force | Out-Null

        Get-ConnectorDefinitionSummary $installDirPath | Should -Be "No DB connector definitions"
    }

    It "includes the connector's directory name and its raw definition XML, quotes and all" {
        # Regression coverage for the real production crash this is ported from (NGI's Tidemann
        # connector): a definition file containing a double quote (e.g. <page name="Database">)
        # must survive completely unescaped and unmodified, since this project's report sections
        # never re-parse a rendered value as PowerShell source in the first place.
        $installDirPath = Join-Path $TestDrive "saga-install-one-connector"
        New-TestConnectorDefinition $installDirPath "Tidemann" '<page name="Database"><setting key="x" value="y" /></page>'

        $result = Get-ConnectorDefinitionSummary $installDirPath
        $escapedXml = [regex]::Escape('<page name="Database"><setting key="x" value="y" /></page>')

        $result | Should -Match "Connector: Tidemann"
        $result | Should -Match $escapedXml
    }

    It "includes every connector that has a definition file, and skips ones that don't" {
        $installDirPath = Join-Path $TestDrive "saga-install-multiple-connectors"
        New-TestConnectorDefinition $installDirPath "fileserver" "<rules></rules>"
        New-TestConnectorDefinition $installDirPath "exchange" "<rules></rules>"
        New-Item -ItemType Directory -Path (Join-Path $installDirPath "volumes\Connector\sharepoint") -Force | Out-Null

        $result = Get-ConnectorDefinitionSummary $installDirPath

        $result | Should -Match "Connector: fileserver"
        $result | Should -Match "Connector: exchange"
        $result | Should -Not -Match "Connector: sharepoint"
    }
}
