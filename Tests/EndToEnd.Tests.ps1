# Runs the real entry point with no mocks at all - the layer that catches integration bugs unit
# tests can't see (like the two real bugs this project already found on a production host), at the
# cost of depending on real system state. Assertions check output *shape* rather than exact values.

BeforeAll {
    $ayfieInspectorScript = Resolve-Path "$PSScriptRoot/../Invoke-AyfieInspector.ps1"
}

Describe "Invoke-AyfieInspector end-to-end" {
    It "produces a complete, error-free text report with every section, in the expected order" {
        # -skipFirewallCheck keeps this fast; the Dashboard API calls are expected to fail on a
        # dev/CI machine (no real Ayfie Index installation here) and should degrade gracefully
        # rather than error out - that graceful-degradation behavior is exactly what's asserted.
        Push-Location $TestDrive
        try {
            $output = (& $ayfieInspectorScript -outputFormat text -outputDestination terminal -skipFirewallCheck 2>$null) -join "`n"
        } finally {
            Pop-Location
        }

        $sectionOrder = @(
            "REPORT INFO", "CERTIFICATES", "HOST IDENTITY", "NETWORK", "SYSTEM RESOURCES",
            "RESOURCE USAGE", "FIREWALL OPENINGS", "AUTHENTICATION METHOD",
            "DATA SOURCE USER SYNCING", "SAGA INFO", "BACKUPS", "CUSTOM.ENV FILE CONTENT",
            "SCHEDULED RESTART", "DATABASE INFO", "SOLR INFO", "CUSTOM REFINERS",
            "DOCKER IMAGES CURRENTLY IN USE", "DATA SOURCE CONNECTIONS", "CUSTOM INDEX RULES",
            "CUSTOM SEARCH RULES"
        )
        $previousIndex = -1
        foreach ($section in $sectionOrder) {
            $index = $output.IndexOf($section)
            $index | Should -BeGreaterThan $previousIndex -Because "'$section' should appear, in order"
            $previousIndex = $index
        }

        $output | Should -Not -Match "ERROR -->"
    }

    It "never has two consecutive blank lines between sections" {
        # Regression test: the seam between Winspect's own report and AyfieInspector's appended
        # sections (RESOURCE USAGE -> FIREWALL OPENINGS specifically, since RESOURCE USAGE is
        # Winspect's last section absent the optional GMSA/FILE WRITE ERRORS ones) previously showed
        # two blank lines where every other section boundary in the report showed exactly one -
        # Start-AyfieInspector added an extra separator newline on top of the one Winspect's own
        # New-SectionOutput already appends to every section.
        Push-Location $TestDrive
        try {
            $output = (& $ayfieInspectorScript -outputFormat text -outputDestination terminal -skipFirewallCheck 2>$null) -join "`n"
        } finally {
            Pop-Location
        }

        $reportLines = @($output -split "`r`n")
        # Trim the trailing blank run first - the report's last section (whichever one it happens
        # to be) naturally ends with its own trailing blank-line separator with nothing after it,
        # which isn't the bug; only an interior double-blank, between two sections that both have
        # content, is.
        $lastContentIndex = $reportLines.Count - 1
        while ($lastContentIndex -ge 0 -and $reportLines[$lastContentIndex].Trim() -eq "") {
            $lastContentIndex--
        }
        $contentLines = $reportLines[0..$lastContentIndex]
        $consecutiveBlankLineIndexes = 0..($contentLines.Count - 2) | Where-Object {
            $contentLines[$_].Trim() -eq "" -and $contentLines[$_ + 1].Trim() -eq ""
        }
        $consecutiveBlankLineIndexes | Should -BeNullOrEmpty
    }

    It "writes a report file into the current directory when the destination includes file" {
        Push-Location $TestDrive
        try {
            & $ayfieInspectorScript -outputFormat text -outputDestination file -skipFirewallCheck 2>$null | Out-Null
            Test-Path (Join-Path $TestDrive "ayfieinspector-report.txt") | Should -BeTrue
        } finally {
            Pop-Location
        }
    }

    It "skips the firewall check and says so when -skipFirewallCheck is passed" {
        Push-Location $TestDrive
        try {
            $output = (& $ayfieInspectorScript -outputFormat text -outputDestination terminal -skipFirewallCheck 2>$null) -join "`n"
        } finally {
            Pop-Location
        }

        $output | Should -Match "Skipped due to -skipFirewallCheck"
    }
}
