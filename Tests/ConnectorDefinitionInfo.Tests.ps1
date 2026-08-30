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

Describe "Test-HasRestrictedSecuritySource" {
    # Used by Get-AuthenticationMethodSummary to say something concrete about whether an
    # authenticated session (e.g. a local Keycloak account) can actually see restricted data -
    # confirmed on a real KTH host where a connector granted every document to S-1-1-0 ("Everyone").

    It "reports false when every SID found is Everyone (S-1-1-0)" {
        $installDirPath = Join-Path $TestDrive "saga-install-everyone-only"
        New-TestConnectorDefinition $installDirPath "GenericSQL" '<SecuritySources><add name="everyone" type="StaticSecuritySource"><SID value="S-1-1-0" /></add></SecuritySources>'

        Test-HasRestrictedSecuritySource $installDirPath | Should -BeFalse
    }

    It "reports true when a SID other than Everyone is found" {
        $installDirPath = Join-Path $TestDrive "saga-install-restricted"
        New-TestConnectorDefinition $installDirPath "SharePoint" '<SecuritySources><add name="scoped" type="StaticSecuritySource"><SID value="S-1-5-21-111-222-333-1001" /></add></SecuritySources>'

        Test-HasRestrictedSecuritySource $installDirPath | Should -BeTrue
    }

    It "reports false (same as all-Everyone) when no connector has a SecuritySources block at all" {
        # Morten's call: a missing SecuritySources block is treated the same as everything being
        # Everyone - both mean "no per-user restriction found", not a separate third case.
        $installDirPath = Join-Path $TestDrive "saga-install-no-security-sources"
        New-TestConnectorDefinition $installDirPath "fileserver" "<ConnectorDefinition></ConnectorDefinition>"

        Test-HasRestrictedSecuritySource $installDirPath | Should -BeFalse
    }

    It "reports false when the connectors root doesn't exist at all" {
        $installDirPath = Join-Path $TestDrive "saga-install-no-connectors-dir-2"
        New-Item -ItemType Directory -Path $installDirPath -Force | Out-Null

        Test-HasRestrictedSecuritySource $installDirPath | Should -BeFalse
    }

    It "reports false when no install directory is known" {
        Test-HasRestrictedSecuritySource "" | Should -BeFalse
    }

    It "reports true if even one connector among several has a restricted SID" {
        $installDirPath = Join-Path $TestDrive "saga-install-mixed"
        New-TestConnectorDefinition $installDirPath "web" '<SecuritySources><add name="everyone" type="StaticSecuritySource"><SID value="S-1-1-0" /></add></SecuritySources>'
        New-TestConnectorDefinition $installDirPath "SharePoint" '<SecuritySources><add name="scoped" type="StaticSecuritySource"><SID value="S-1-5-21-111-222-333-1001" /></add></SecuritySources>'

        Test-HasRestrictedSecuritySource $installDirPath | Should -BeTrue
    }
}
