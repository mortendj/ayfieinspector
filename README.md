# AyfieInspector

AyfieInspector reports on installation-specific details of **Ayfie Index** (formerly known as
**Ayfie Locator**), on top of the generic Windows host facts already covered by
[Winspect](https://github.com/mortendj/winspect). It's aimed at anyone who needs a quick,
consistent view of what's actually configured on a given Ayfie Index installation — rule engine
customizations, search refiners, the scheduled restart task, outbound connectivity, and the
gateway certificate — without having to piece it together from several different admin surfaces
by hand.

> **Status:** early, actively developed (v0.15.0). The current release covers the rule engine,
> custom refiners, the Solr document count, the scheduled restart task, an outbound firewall
> connectivity check, the Saga gateway certificate, the authentication method, basic installation
> info (install directory, Saga version, branding, gateway hostname, OS support status), the
> redacted `custom.env` file content, and the data source connections (with settings redacted).

> **Independent, unofficial project.** Not affiliated with, endorsed by, or sponsored by Ayfie
> Group. "Ayfie", "Ayfie Index", and "Ayfie Locator" are trademarks of their respective owner.

## Features

- **Custom rule engine rules:** every rule actually entered via the rule editor (not
  development-inserted or connector-installation rules), reported separately for the index side
  and the query side so the two are never shown as one merged list — each with its type, version,
  sort order, last-modified timestamp, and full rule definition.
- **Custom refiners:** every search refiner that isn't part of the built-in default set, with its
  field name, facet type, selection limit, enabled state, and sort order.
- **Solr document count:** the current source reference count.
- **Scheduled restart task:** whether a scheduled restart task exists, and if so, its schedule,
  the command it runs, and the user it runs as.
- **Outbound firewall openings:** which of the external endpoints an Ayfie Index installation
  needs reachable actually are, reported separately from a couple of interchangeable "alternate"
  endpoints where only one of the two needs to be reachable.
- **Authentication method:** whether this installation is set up for Entra ID (identity provider)
  or Active Directory (user federation), queried directly from Keycloak's own database. Reports a
  clean "Not configured" for a genuinely unconfigured deployment — a legitimate, common state
  during setup, confirmed on real customer hosts — rather than treating it as an error.
- **Saga info:** install directory, Saga version, branding, and the configured gateway hostname —
  auto-discovered from the running installation the same way the gateway certificate check already
  is, so this adds no extra Docker calls of its own. Also reports whether the host's OS is one
  Ayfie Index (Saga) is actually qualified to run on, as an informational warning rather than a
  blocker — unlike the internal tool this check is ported from, an unsupported OS here never
  prevents the rest of the report from running.
- **Custom.env file content:** the `custom.env` overrides file, with values for any key matching a
  sensitive-naming convention (`PASSWORD`, `SECRET`, `API_KEY`, `API_TOKEN`) dropped entirely rather
  than shown or masked.
- **Data source connections:** every connector's connections (display name, enabled state,
  document count) and their settings, queried from the connector-broker API. Settings matching a
  sensitive-naming convention (`Token`, `Secret`, `Password`, `CompanyGuid`, `Key`) are dropped
  entirely rather than shown or masked - same redaction principle as the custom.env feature above,
  with its own token list since connector setting names follow a different naming convention.
- **Saga gateway certificate:** identifies and reports the expiration of the actual Ayfie/Saga
  gateway certificate — a file-backed certificate the generic Windows certificate store scan below
  can never see. Checked both live over HTTPS against the configured gateway hostname (proof of
  what's actually being served right now, auto-discovered from the running installation's `.env`)
  and against the certificate file itself, with their issuers compared: a match reports one clean
  line, a mismatch is flagged explicitly with both certificates shown side by side. The most common
  real cause of a mismatch is a local TLS-inspecting security proxy silently re-signing outbound
  HTTPS on the host - confirmed on a real customer host, where the live check alone would have
  reported the proxy's substituted certificate as if it were genuine. Falls back to whichever check
  succeeds if the other's endpoint/file isn't reachable (e.g. Saga is stopped). Can be pointed at
  an explicit file instead (skipping the live check entirely) for checking a host before Saga is
  even installed.
- **Generic host facts:** everything Winspect itself reports — host identity, network adapters,
  CPU/RAM/disk capacity and usage, and certificate expirations — included in the same combined
  report, with an `AyfieInspector version` line added next to Winspect's own version line so a
  saved report is always attributable to the exact release that produced it.
- **Output formats:** plain text, Markdown, or HTML.
- **Output destinations:** terminal, a report file, or both.
- **Structured logging:** off by default, configurable up to trace-level detail. Writes two log
  files (one for AyfieInspector's own steps, one for the underlying Winspect run), always in the
  same folder as the report.

## Requirements

- Must run **on the Ayfie Index host itself** — the rule engine, refiner, and Solr count checks
  go through an internal API that isn't designed to be reached remotely.
- Windows, with Windows PowerShell 5.1 or PowerShell 7+.
- Run elevated (as Administrator) to get real disk speed/latency numbers in the Winspect portion
  of the report.
- Docker CLI access, to auto-discover the gateway certificate's file location and the configured
  gateway hostname from the running installation's `.env`. Not needed if `-certificateFilePath` is
  given explicitly instead (e.g. checking a host before Saga is installed, when there's no running
  installation to discover from).
- Outbound network access to the gateway hostname on port 443, for the live HTTPS certificate
  check. Not required - the check falls back to the certificate file if the endpoint can't be
  reached, and says so in the report.

## Usage

```powershell
# Default: plain text report, printed to the terminal and saved to ayfieinspector-report.txt
.\Invoke-AyfieInspector.ps1

# Markdown report, skip the outbound firewall check
.\Invoke-AyfieInspector.ps1 -outputFormat markdown -skipFirewallCheck

# Verbose troubleshooting log
.\Invoke-AyfieInspector.ps1 -logLevel debug

# Point at a non-default Dashboard API root (e.g. non-standard port or path)
.\Invoke-AyfieInspector.ps1 -dashboardApiRootUrl "http://localhost:8080/Dashboard/api"

# Check a host before Saga is installed there, using an explicit certificate path
.\Invoke-AyfieInspector.ps1 -certificateFilePath "C:\path\to\gateway.crt"
```

| Parameter | Values | Default | Description |
|---|---|---|---|
| `-outputFormat` | `text`, `markdown`, `html` | `text` | Report style. |
| `-outputDestination` | `terminal`, `file`, `both` | `both` | Where the report goes. |
| `-dashboardApiRootUrl` | URL | `http://localhost/Dashboard/api` | Root URL for the rule engine, refiner, and Solr count checks. |
| `-connectorApiRootUrl` | URL | `http://localhost/api/connector-broker/v1` | Root URL for the data source connections check. |
| `-logLevel` | `trace`, `debug`, `info`, `warning`, `error`, `off` | `off` | Logging verbosity. |
| `-skipFirewallCheck` | switch | off | Skip the outbound connectivity check (adds noticeable time otherwise). |
| `-certificateFilePath` | path | auto-discovered | Path to the Saga gateway certificate file; only needed to override auto-discovery, e.g. when checking a host before Saga is installed. Setting this skips the live HTTPS check entirely (no gateway hostname is resolved). |
| `-winspectPath` | path | auto-detected | Path to Winspect's entry script; only needed if it's not where AyfieInspector expects it. |

## Sample output

```
#################### FIREWALL OPENINGS #####################
Reachable sites:
    github.com
    docker.io
    hub.docker.com
Non-reachable sites:
    example-non-reachable-site.com
Alternate sites:
    Reachable: alternate-cdn-example.net
    Non-reachable: alternate-cdn-example.org

################## AUTHENTICATION METHOD ###################
Authentication method: Entra ID

######################## SAGA INFO #########################
Install directory: d:\program files\ayfie\saga\
Saga version: 7.19.0
Branding: ayfie
Gateway hostname: engine.example.com
OS supported by Saga: Supported

################# CUSTOM.ENV FILE CONTENT ##################
AYFIE_SAGA_BRANDING_KEY=ayfie
AYFIE_SAGA_HOST_NAME=engine.example.com

#################### SCHEDULED RESTART #####################
Task name: Restart-Saga
Task execution time: Every Sunday at 03:00
Task command: .\stop-saga.ps1 .\saga.ps1 -Quiet -AcceptEula
Task user: ayfie

######################## SOLR INFO #########################
Source reference count: 842,315

##################### CUSTOM REFINERS ######################
Refiners:
    Department
        RefinerName: Department
        FieldName: via_ssimd_department
        FacetType: FacetField
        SelectionLimit: 1000
        Enabled: True
        SortOrder: 5

################# DATA SOURCE CONNECTIONS ##################
NetData (fileserver)
    Enabled: True
    Document count: 44907
    Settings:
        StartPath=\\host\NetData
        FilenameFilterMode=2

#################### CUSTOM INDEX RULES ####################
Rules:
    Custom Metadata Mapping
        RuleType: custom
        Version: 1
        SortOrder: 10
        LastModifiedDate: 2026-03-11T09:12:44.000000Z
        ConnectorTypeId:
        Definition:
            <rules LastModification="3/11/2026 9:12:44 AM">
              <rule name="Map department field">
                <conditions>
                  <field name="config.connector_type@connector" value="web" multiMode="any" />
                </conditions>
                <actions>
                  <insert field="via_ssimd_department" multiMode="last" ignorecase="false" duplicate="false">
                    <set condition="empty">
                      <field name="meta_department" multimodefield="last" />
                    </set>
                    <exit condition="empty" process="false" />
                  </insert>
                </actions>
              </rule>
            </rules>

################### CUSTOM SEARCH RULES ####################
Rules:
    No rules found
```

(The Winspect-generated sections — REPORT INFO (with an added `AyfieInspector version` line right
alongside Winspect's own), CERTIFICATES, SAGA CERTIFICATE (Winspect's generic "additional
certificate" check, given AyfieInspector's own section title — hostname and file both resolved by
AyfieInspector and passed through to Winspect, which checks the hostname live over HTTPS first and
only falls back to the file if that's unreachable, always stating which one actually produced the
result), HOST IDENTITY, NETWORK, SYSTEM RESOURCES, RESOURCE USAGE — appear first in the actual
report; see
[Winspect's own README](https://github.com/mortendj/winspect#sample-output) for what those look
like.)

## Building a release package

```powershell
.\Build-AyfieInspectorPackage.ps1
```

Packages `Invoke-AyfieInspector.ps1` and `src/` together with a fresh copy of Winspect into
`dist/ayfieinspector-vX.Y.Z.zip`, with the version read from `src/Constants.ps1`. Extract it
anywhere and run `Invoke-AyfieInspector.ps1` from inside the extracted `AyfieInspector/` folder —
Winspect is bundled right alongside it, so nothing else needs to be installed separately.

## Project layout

```
Invoke-AyfieInspector.ps1        entry point: parameter declarations, dot-sources src/, kicks off the run
Build-AyfieInspectorPackage.ps1  packages a release zip with Winspect bundled inside
src/
  Constants.ps1                  version info, default refiners, restart task name, firewall URLs
  DashboardApi.ps1               shared API call helper, source reference count
  RuleEngineInfo.ps1             rule engine rules - fetch and summarize
  RefinerInfo.ps1                custom refiners - fetch and summarize
  ScheduledTaskInfo.ps1          scheduled restart task - fetch and summarize
  FirewallInfo.ps1               outbound connectivity check
  SagaCertificateInfo.ps1        Saga gateway certificate path - auto-discovery and override
  AuthenticationInfo.ps1         identity provider / user federation provider counts from Keycloak
  SagaInfo.ps1                   Saga version from git.version
  MainOrchestration.ps1          builds each report section and assembles the combined report
```

## Running tests

Tests use [Pester](https://pester.dev/) 5.x:

```powershell
Invoke-Pester -Path .\Tests
```

The suite mirrors Winspect's own layering: plain unit tests for pure functions (formatting,
weekday/time parsing, URL parsing), tests that mock only the real boundary (the Dashboard API call,
`Get-ScheduledTask`, `Test-NetConnection`/`Invoke-WebRequest`) and run the actual logic on top,
tests for the report-section-assembly functions, and a final end-to-end smoke test that runs the
real entry point with no mocks at all, asserting on section order and output shape rather than
exact values.

## Contributing

This is an early-stage personal project, but issues and pull requests are welcome.

## Author

Morten Johnsen — [github.com/mortendj](https://github.com/mortendj)

## License

[MIT](LICENSE)
