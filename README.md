# AyfieInspector

AyfieInspector reports on installation-specific details of **Ayfie Index** (formerly known as
**Ayfie Locator**), on top of the generic Windows host facts already covered by
[Winspect](https://github.com/mortendj/winspect). It's aimed at anyone who needs a quick,
consistent view of what's actually configured on a given Ayfie Index installation — rule engine
customizations, search refiners, the scheduled restart task, outbound connectivity, and the
gateway certificate — without having to piece it together from several different admin surfaces
by hand.

> **Status:** early, actively developed (v0.22.0). The current release covers the rule engine,
> custom refiners, Solr info (document count, index languages/memory/stack size/index size), the
> scheduled restart task, an outbound firewall connectivity check, the Saga gateway certificate,
> the authentication method, AD/Azure AD data source syncing, database info, backups, Docker
> images currently in use, an optional gMSA account check, installation info (install directory,
> Saga version, branding, gateway hostname, OS support status, installed/in-use connectors), Saga
> license info (customer ID, activation/expiration dates, user/document capacity, licensed
> features), the redacted `custom.env` file content, the data source connections (with settings
> redacted, plus any other fields the connection API happens to return, e.g. repositories/security),
> Supervisor info (report engine container status, license, Lingo configuration),
> Personal Assistant info (operational mode and, on Saga versions before the models were dropped
> from `docker/.env`, the configured chat models), Lingo info (enabled state, container status,
> licenses, language/data type, and thread/recycle settings), and a diff of the running
> `docker/.env` against its as-shipped reference (removed/added/modified variables, excluding
> anything accounted for by `custom.env`), the raw database connector configuration definitions
> for every connector that has one, and detailed SSL certificate info (issuing authority, subject
> alternative names, private key encryption status).

> **Independent, unofficial project.** Not affiliated with, endorsed by, or sponsored by Ayfie
> Group. "Ayfie", "Ayfie Index", and "Ayfie Locator" are trademarks of their respective owner.

## Features

- **Custom rule engine rules:** every rule actually entered via the rule editor (not
  development-inserted or connector-installation rules), reported separately for the index side
  and the query side so the two are never shown as one merged list — each with its type, version,
  sort order, last-modified timestamp, and full rule definition.
- **Custom refiners:** every search refiner that isn't part of the built-in default set, with its
  field name, facet type, selection limit, enabled state, and sort order.
- **Solr info:** index languages, Java memory and stack size settings (from the running
  installation's `.env`), the index's on-disk size (recursive scan of the Solr data directory,
  formatted with an explicit invariant culture so the decimal separator doesn't depend on the
  host's own locale), and the current source reference count.
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
  prevents the rest of the report from running. Also reports installed connectors from two
  independent sources (the Management Console API, and a scan of the install directory's `plugins`
  folder), which connectors actually have at least one connection configured, and which connector
  containers are currently running.
- **Data source user syncing:** whether AD/Azure AD user syncing is enabled, from the running
  installation's `.env`.
- **Database info:** database type, name, user, server, and port, from the running installation's
  `.env`.
- **Supervisor info:** the report engine (`report-engine-ui`) container's running status, whether
  the license includes the Report Engine capability, and its Lingo configuration - the same
  language/data-type value the Lingo info section below reports, since the report engine consumes
  Lingo's output directly.
- **Personal Assistant info:** the operational mode (`off`, `limited`, or `full`), and - only on Saga versions
  before major version 7, matching when the internal tool this is ported from stops reporting them
  - the configured main/high-quality/high-quality-plus chat models and their display names, from
    the running installation's `.env`.
- **Lingo info:** whether Lingo is enabled, the `ayfie-lingo` container's running status, whether
  the license includes the Lingo Standard and Lingo GDPR capabilities, the configured
  language/data-type (regular or PII), and the pipeline thread count and recycle
  (memory/runs/time) settings, from the running installation's `.env`.
- **Backups:** number of backups found, the most recent backup's timestamp, and the total size on
  disk of the backup directory.
- **Docker images currently in use:** the image:tag of every currently running container.
- **gMSA account check** (opt-in, needs `-gmsaAccountName`): passed straight through to Winspect's
  own gMSA validation, adding a `GMSA ACCOUNT` section reporting the account name and whether it
  validates successfully.
- **Saga license info:** customer ID, activation/expiration dates, user/document capacity, and
  licensed features - queried directly from the licensing container's own API. Only currently-valid
  licenses count towards capacity and features (an installation can hold more than one - e.g. a
  base license plus an add-on - so capacities are summed and features are concatenated across all
  of them, not deduplicated). The customer ID is still shown even when every license has expired,
  since it's identifying information rather than a capacity/feature claim that would be misleading
  to report for an expired license. The customer's name is also spliced into the `REPORT INFO`
  section (as `Customer`, right after the section header) whenever it's known - simply omitted, not
  shown as "Unavailable", when it isn't (e.g. checking a host before Saga is installed).
- **Expirations and capacity depletions:** days left until the Saga license expires (`Perpetual` for
  a perpetual license, `No valid license` when there's genuinely none). Deliberately doesn't
  duplicate the SSL certificate's own days-remaining figure, which is already shown in the `SAGA
  CERTIFICATE` section.
- **Custom.env file content:** the `custom.env` overrides file, with values for any key matching a
  sensitive-naming convention (`PASSWORD`, `SECRET`, `API_KEY`, `API_TOKEN`) dropped entirely rather
  than shown or masked.
- **Temporary .env file changes:** diffs the running installation's `docker/.env` against the
  as-shipped reference extracted from `Ayfie.Saga.zip` (the install bundle Saga itself keeps at the
  install root) - reporting variables removed, added, or modified relative to that reference.
  Anything already accounted for by `custom.env` is excluded from the added/modified lists, since
  that's a supported override rather than an unexpected hand-edit, and `COMPOSE_FILE` is always
  excluded from the modified list since Saga's own tooling legitimately rewrites it depending which
  optional add-ons (chat, report engine) are enabled.
- **Data source connections:** every connector's connections (display name, enabled state,
  document count) and their settings, queried from the connector-broker API. Settings matching a
  sensitive-naming convention (`Token`, `Secret`, `Password`, `CompanyGuid`, `Key`) are dropped
  entirely rather than shown or masked - same redaction principle as the custom.env feature above,
  with its own token list since connector setting names follow a different naming convention. Any
  other field the API happens to return for a connection - e.g. `repositories`, `security` - is
  rendered too, generically (recursing into nested objects/arrays), rather than silently dropped by
  a fixed field list.
- **Database connector configurations:** the raw `ConnectorDefinition.xml` content for every
  connector under `volumes\Connector` that has one, rendered as-is (never re-parsed as anything
  other than report text) - a real production crash (NGI's Tidemann connector, whose definition
  contained a double quote) in the older tool this is ported from came from wrapping that same raw
  XML in a string and evaluating it as PowerShell source, which this project's plain scriptblock
  report sections never do in the first place.
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
- **SSL certificate info:** issuing certificate authority, subject alternative names, and the
  private key's encryption status (`Encrypted`, `Unencrypted`, or - since it isn't easily
  determined from the PEM header alone - a distinct "RSA key" case), read from the certificate file
  itself (the private key only ever exists on disk, never over the live HTTPS check).
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
  gateway hostname from the running installation's `.env`, to list running containers/images (Saga
  info's connector container check, Docker images currently in use), and to resolve the licensing
  container's IP for the Saga license info check. Not needed for the certificate/install-dir
  discovery if `-certificateFilePath` is given explicitly instead (e.g. checking a host before Saga
  is installed, when there's no running installation to discover from).
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

# Also validate a gMSA account
.\Invoke-AyfieInspector.ps1 -gmsaAccountName "domain\sagagMSA$"
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
| `-gmsaAccountName` | account name | none | Name of a gMSA to validate, passed straight through to Winspect. Adds a `GMSA ACCOUNT` section when supplied; omitted entirely otherwise. |
| `-winspectPath` | path | auto-detected | Path to Winspect's entry script; only needed if it's not where AyfieInspector expects it. |

## Sample output

```
################## SSL CERTIFICATE INFO #####################
Certificate authority: CN=DigiCert Global CA, O=DigiCert Inc, C=US
Subject alternative names: search.example.com
Private key: Unencrypted

########### EXPIRATIONS AND CAPACITY DEPLETIONS ############
Days left of Saga license: 94

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

################# DATA SOURCE USER SYNCING #################
AD and Azure AD syncing: true

######################## SAGA INFO #########################
Install directory: d:\program files\ayfie\saga\
Saga version: 7.19.0
Branding: ayfie
Gateway hostname: engine.example.com
OS supported by Saga: Supported
Installed connectors (Management Console): fileserver exchange sharepoint
Installed connectors (plugins directory): fileserver exchange
Connectors in actual use: fileserver exchange
Running connector containers: 
 - fileserver
 - exchange

######################### BACKUPS ##########################
Number of backups: 2
Latest backup: 2026-03-21 17:59
Total size: 151.751 MB

#################### SAGA LICENSE INFO #####################
Customer Id: 1234567
Activation date (utc): 2022-06-01T15:12:58Z
Expiration date (utc): 2027-01-31T13:08:22Z
User capacity: 100
Document capacity: 1000000
Licensed features: 
Connector: File Server Connector
Function: SharePoint Online

################# CUSTOM.ENV FILE CONTENT ##################
AYFIE_SAGA_BRANDING_KEY=ayfie
AYFIE_SAGA_HOST_NAME=engine.example.com

################ TEMPORARY .ENV FILE CHANGES ################
Removed variables: None
Added variables: None
Modified variables: AYFIE_SAGA_INDEX_LANGUAGES (en;nb;sv)

#################### SCHEDULED RESTART #####################
Task name: Restart-Saga
Task execution time: Every Sunday at 03:00
Task command: .\stop-saga.ps1 .\saga.ps1 -Quiet -AcceptEula
Task user: ayfie

###################### DATABASE INFO #######################
Database type: MSSQL
Database name: Locator
Database user: postgres
Database server: dbserver.example.com
Database port: 1433

###################### SUPERVISOR INFO #####################
Report engine container: Running
Report engine license: Has license
Report engine Lingo configuration: nb (regular, not PII)

#################### PERSONAL ASSISTANT ####################
Operational mode: full

######################## LINGO INFO ########################
Lingo enabled: true
Lingo container: Running
Lingo standard license: Has license
Lingo GDPR license: No license
Lingo language (and data type): nb (regular, not PII)
Lingo threads (a.k.a pipeline pool size): 4
Lingo recycle memory threshold: 2048
Lingo recycle runs: 1000
Lingo recycle time (seconds): 3600

######################## SOLR INFO #########################
Solr index languages: en;nb
Solr java memory: -Xms8g -Xmx8g
Solr java stack size: -Xss256k
Solr index size: 72.437 GB
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

############## DOCKER IMAGES CURRENTLY IN USE ##############
ayfiehub/locator:7.19.0
ayfiehub/solr:7.4.0
ayfiehub/gateway-keycloak:6.1.0

################# DATA SOURCE CONNECTIONS ##################
NetData (fileserver)
    Enabled: True
    Document count: 44907
    security:
        authRealm: saga
    repositories:
        name: Repo1
        path: \\host\Repo1
    Settings:
        StartPath=\\host\NetData
        FilenameFilterMode=2

############ DATABASE CONNECTOR CONFIGURATIONS #############
Connector: Tidemann
<ConnectorDefinition>
  <ConnectionString>Server=dbserver.example.com;Database=Tidemann;</ConnectionString>
</ConnectorDefinition>

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
alongside Winspect's own, and a `Customer` line right after the section header when the customer
name is known), CERTIFICATES, SAGA CERTIFICATE (Winspect's generic "additional
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
  SagaCertificateInfo.ps1        Saga gateway certificate path/detail - auto-discovery, override, CA/SAN/private key status
  AuthenticationInfo.ps1         identity provider / user federation provider counts from Keycloak
  SagaInfo.ps1                   Saga version, OS support check, installed connectors (API + plugins dir), connectors in use
  EnvFileInfo.ps1                custom.env file content, redacted
  EnvConfigDiffInfo.ps1          docker/.env vs. as-shipped reference (Ayfie.Saga.zip) diff
  ConnectorApi.ps1               connector-broker API wrapper (installed connectors, connections, settings)
  DataSourceConnectionInfo.ps1   data source connections summary (incl. generic extra fields), settings redacted
  ConnectorDefinitionInfo.ps1    raw per-connector ConnectorDefinition.xml content
  DatabaseInfo.ps1               database type/name/user/server/port, AD/Azure AD sync flag
  DirectorySizeInfo.ps1          recursive directory size scan, invariant-culture formatted
  DockerInfo.ps1                 running containers/images, running connector containers
  BackupInfo.ps1                 backup count, latest backup, total size
  LicenseInfo.ps1                Saga license info (customer ID, dates, capacity, features)
  LingoInfo.ps1                  Lingo enabled state, language/data type, thread/recycle settings
  PersonalAssistantInfo.ps1      Personal Assistant operational mode and configured chat models
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
