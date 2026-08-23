# AyfieInspector

AyfieInspector reports on installation-specific details of **Ayfie Index** (formerly known as
**Ayfie Locator**), on top of the generic Windows host facts already covered by
[Winspect](https://github.com/mortendj/winspect). It's aimed at anyone who needs a quick,
consistent view of what's actually configured on a given Ayfie Index installation — rule engine
customizations, search refiners, the scheduled restart task, and outbound connectivity — without
having to piece it together from several different admin surfaces by hand.

> **Status:** early, actively developed (v0.3.0). The current release covers the rule engine,
> custom refiners, the Solr document count, the scheduled restart task, and an outbound firewall
> connectivity check.

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
- **Generic host facts:** everything Winspect itself reports — host identity, network adapters,
  CPU/RAM/disk capacity and usage, and certificate expirations — included in the same combined
  report.
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
```

| Parameter | Values | Default | Description |
|---|---|---|---|
| `-outputFormat` | `text`, `markdown`, `html` | `text` | Report style. |
| `-outputDestination` | `terminal`, `file`, `both` | `both` | Where the report goes. |
| `-dashboardApiRootUrl` | URL | `http://localhost/Dashboard/api` | Root URL for the rule engine, refiner, and Solr count checks. |
| `-logLevel` | `trace`, `debug`, `info`, `warning`, `error`, `off` | `off` | Logging verbosity. |
| `-skipFirewallCheck` | switch | off | Skip the outbound connectivity check (adds noticeable time otherwise). |
| `-winspectPath` | path | auto-detected | Path to Winspect's entry script; only needed if it's not where AyfieInspector expects it. |

## Sample output

```
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

##################### CUSTOM REFINERS ######################
Refiners:
    Department
        RefinerName: Department
        FieldName: via_ssimd_department
        FacetType: FacetField
        SelectionLimit: 1000
        Enabled: True
        SortOrder: 5

######################## SOLR INFO #########################
Source reference count: 842,315

#################### SCHEDULED RESTART #####################
Task name: Restart-Saga
Task execution time: Every Sunday at 03:00
Task command: .\stop-saga.ps1 .\saga.ps1 -Quiet -AcceptEula
Task user: ayfie

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
```

(The Winspect-generated sections — REPORT INFO, HOST IDENTITY, NETWORK, SYSTEM RESOURCES, RESOURCE
USAGE, CERTIFICATES — appear first in the actual report; see
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
Invoke-AyfieInspector.ps1        entry point: parameter declarations, runs Winspect, adds Ayfie sections
Build-AyfieInspectorPackage.ps1  packages a release zip with Winspect bundled inside
src/
  Constants.ps1                  version info, default refiners, restart task name, firewall URLs
  DashboardApi.ps1               shared API call helper, source reference count
  RuleEngineInfo.ps1             rule engine rules - fetch and summarize
  RefinerInfo.ps1                custom refiners - fetch and summarize
  ScheduledTaskInfo.ps1          scheduled restart task - fetch and summarize
  FirewallInfo.ps1               outbound connectivity check
```

## Contributing

This is an early-stage personal project, but issues and pull requests are welcome.

## Author

Morten Johnsen — [github.com/mortendj](https://github.com/mortendj)

## License

[MIT](LICENSE)
