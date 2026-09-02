################## VERSION ##################

# Named distinctly from Winspect's own $SCRIPT_VERSION/$SCRIPT_NAME (Constants.ps1) - Invoke-
# AyfieInspector.ps1 dot-sources Winspect's Constants.ps1 too, and those names are already claimed
# there.
$AYFIE_INSPECTOR_VERSION           = "1.1.0"
$AYFIE_INSPECTOR_VERSION_TIMESTAMP = "2026-08-31"
$AYFIE_INSPECTOR_NAME              = "AyfieInspector"
$AYFIE_INSPECTOR_VERSION_STRING    = "$AYFIE_INSPECTOR_NAME v. $AYFIE_INSPECTOR_VERSION ($AYFIE_INSPECTOR_VERSION_TIMESTAMP)"

################## REFINERS ##################

# Refiners built into every Saga installation, regardless of customization - anything not in this
# list is a genuine customer/admin-added refiner.
$DEFAULT_REFINERS = @(
    "DateModified",
    "Repository",
    "Source",
    "FileType",
    "FileExtension",
    "Attachments",
    "IsDocumentAnAttachment",
    "Flags",
    "DocumentHasAttachments",
    "Labels",
    "Timeline",
    "DocumentLanguage",
    "Author",
    "TaskCompleted"
)

################## GATEWAY CERTIFICATE ##################

$LICENSING_CONTAINER_NAME     = "ayfie-saga-licensing"
$DOT_ENV_RELATIVE_PATH        = "docker/.env"
$SSL_CERTIFICATE_DIR          = "volumes/Traefik/certs"
$GATEWAY_CERTIFICATE_NAME_KEY = "AYFIE_SAGA_GATEWAY_CERTIFICATE_NAME"
$GATEWAY_HOSTNAME_KEY         = "AYFIE_SAGA_HOST_NAME"
$AD_SERVICE_ACCOUNT_KEY       = "AYFIE_SAGA_AD_SERVICE_ACCOUNT"
$BRANDING_KEY                 = "AYFIE_SAGA_BRANDING_KEY"
$GIT_VERSION_RELATIVE_PATH    = "git.version"

# Private key files sit alongside the certificate file itself (same name, .key extension) and are
# plain PEM text - their header line alone is enough to tell an encrypted key from an unencrypted
# one, without needing to actually parse the key material.
$ENCRYPTED_KEY_PATTERN        = "BEGIN ENCRYPTED PRIVATE KEY"
$UNENCRYPTED_KEY_PATTERN      = "BEGIN PRIVATE KEY"
$RSA_KEY_PATTERN              = "BEGIN RSA PRIVATE KEY"

################## AUTHENTICATION METHOD ##################

$AUTHORITY_DB_CONTAINER_NAME        = "ayfie-saga-authority-db"
$SAGA_REALM_NAME                    = "saga"
$IDENTITY_PROVIDER_TABLE            = "public.identity_provider"
# Modern Keycloak stores LDAP/AD user federation as a row in the generic public.component table
# (provider_type = org.keycloak.storage.UserStorageProvider), not in the older dedicated
# public.user_federation_provider table - confirmed empty on a real host that has LDAP genuinely
# configured, while public.component correctly has exactly one matching row there.
$COMPONENT_TABLE                    = "public.component"
$USER_STORAGE_PROVIDER_TYPE         = "org.keycloak.storage.UserStorageProvider"
$IDENTITY_PROVIDER_AUTH_METHOD_NAME = "Entra ID"
$USER_FEDERATION_AUTH_METHOD_NAME   = "Active Directory"
# Local, realm-native Keycloak accounts (created directly in the realm, not synced from anywhere)
# are a third way to authenticate that neither identity_provider nor component covers - confirmed on
# a real KTH host where API access kept working via exactly such an account while this section
# reported zero of the two supported mechanisms configured. federation_link IS NULL excludes users
# synced in by a user-storage/federation provider; service_account_client_link IS NULL excludes
# Keycloak's own auto-created per-client service-account users, neither of which is a human/API
# account someone deliberately set up the way a genuine local account is.
$USER_ENTITY_TABLE                  = "public.user_entity"
# saga_admin exists in every Saga realm regardless of whether real application authentication is
# configured - it's the fixed Keycloak console-admin bootstrap account Saga's own deployment
# provisions (KEYCLOAK_USER=saga_admin in index's deploy/saga/docker/TEMPLATE-.env, the baseline
# every install derives its .env from), not something customer-specific. It exists purely to log
# into Keycloak's own admin console, never the actual application, so it must not count toward
# "local accounts that might explain application access" - confirmed by Morten on a real KTH host.
$SAGA_ADMIN_USERNAME                = "saga_admin"
$LOCAL_USER_WHERE_CLAUSE            = "federation_link IS NULL AND service_account_client_link IS NULL AND username != '$SAGA_ADMIN_USERNAME'"

################## OS SUPPORT ##################

# Which Windows Server versions Ayfie Index (Saga) is qualified to run on - reported as a warning,
# not a blocker, unlike the older tool this check is ported from (which throws and aborts an
# unrelated RSAT feature-installation step for any OS not on this list).
$WINDOWS_SERVER_2019 = 'Windows Server 2019'
$WINDOWS_SERVER_2022 = 'Windows Server 2022'
$WINDOWS_SERVER_2025 = 'Windows Server 2025'
$SUPPORTED_OS        = @(
    $WINDOWS_SERVER_2019,
    $WINDOWS_SERVER_2022,
    $WINDOWS_SERVER_2025
)

################## CUSTOM.ENV FILE CONTENT ##################

$CUSTOM_ENV_RELATIVE_PATH = "docker/custom.env"
$SENSITIVE_ENV_TOKENS     = @("PASSWORD", "SECRET", "API_KEY", "API_TOKEN")

################## DATA SOURCE CONNECTIONS ##################

# Same redaction convention as the CUSTOM.ENV FILE CONTENT feature (drop the whole key rather than
# mask the value) but a different token list - connector setting names follow their own naming
# convention (e.g. AuthKey, ClientSecret), not the .env UPPER_SNAKE_CASE one. "Key" included from
# day one here (unlike the older tool this is ported from, which needed a live production find to
# discover its own settings redaction missed a connector's AuthKey field - see
# project_ayfieinspector_gateway_cert_feature.md for that writeup).
$SENSITIVE_CONN_TOKENS = @("Token", "Secret", "Password", "CompanyGuid", "Key")

# Connection API responses carry more than these five fields - e.g. repositories, security - that
# the older tool this is ported from renders too, generically, rather than silently dropping
# anything not on a fixed field list. Anything not in this list gets rendered by
# Get-DataSourceConnectionSummary without needing to know its exact name or shape in advance.
$DATA_SOURCE_CONNECTION_WELL_KNOWN_PROPERTIES = @("id", "displayName", "connectorName", "isEnabled", "documentCount")

################## DATABASE INFO ##################

$DATABASE_TYPE_KEY   = "AYFIE_SAGA_DATABASE_TYPE"
$DATABASE_NAME_KEY   = "AYFIE_SAGA_DATABASE_NAME"
$DATABASE_USER_KEY   = "AYFIE_SAGA_DATABASE_USER_NAME"
$DATABASE_SERVER_KEY = "AYFIE_SAGA_DATABASE_SERVER"
$DATABASE_PORT_KEY   = "AYFIE_SAGA_DATABASE_PORT"

################## DATA SOURCE USER SYNCING ##################

$AD_AAD_SYNC_KEY = "AYFIE_SAGA_AD_AAD_SYNC"

################## SOLR INFO ##################

$SOLR_INDEX_LANGUAGES_KEY = "AYFIE_SAGA_INDEX_LANGUAGES"
$SOLR_JAVA_MEM_KEY        = "SOLR_JAVA_MEM"
$SOLR_JAVA_STACK_SIZE_KEY = "SOLR_JAVA_STACK_SIZE"
$SOLR_INDEX_RELATIVE_PATH = "data/solr"

################## BACKUPS ##################

$BACKUP_RELATIVE_PATH = "backup/data"

################## DOCKER ##################

$CONNECTOR_CONTAINER_NAME_PATTERN = "ayfie-connector-(\w+)"

################## DATABASE CONNECTOR CONFIGURATIONS ##################

$CONNECTORS_ROOT_RELATIVE_PATH       = "volumes\Connector"
$CONNECTOR_DEFINITION_RELATIVE_PATH  = "ConnectorDefinition\ConnectorDefinition.xml"
# The well-known Windows "Everyone" SID - used by Get-AuthenticationMethodSummary (via
# Test-HasRestrictedSecuritySource below) to tell whether a connector's SecuritySources actually
# restrict document access per-user, or grant it to literally everyone.
$EVERYONE_SID                        = "S-1-1-0"

################## CONNECTORS ##################

$CONNECTOR_PLUGINS_RELATIVE_PATH = "plugins"
$CONNECTOR_PLUGIN_PREFIX         = "connector-"

################## SAGA LICENSE INFO ##################

$LICENSING_API_PATH      = "api/licensing/v1/ProductLicense"
$PERPETUAL_LICENSE_LABEL = "Perpetual"

################## SUPERVISOR INFO ##################

$REPORT_ENGINE_CONTAINER_NAME = "report-engine-ui"
$REPORT_ENGINE_LICENSE        = "Report Engine"

################## PERSONAL ASSISTANT ##################

$PA_MODE_KEY               = "AYFIE_SEARCH_UI_FEATURE_CHAT"
$PA_MAIN_MODEL_KEY         = "AYFIE_CHAT_MAIN_MODEL_DEPLOYMENT"
$PA_HQ_MODEL_KEY           = "AYFIE_CHAT_HQ_MODEL_DEPLOYMENT"
$PA_HQ_PLUS_MODEL_KEY      = "AYFIE_CHAT_HQ_PLUS_MODEL_DEPLOYMENT"
$PA_MAIN_MODEL_NAME_KEY    = "AYFIE_CHAT_MAIN_MODEL_DISPLAY_NAME"
$PA_HQ_MODEL_NAME_KEY      = "AYFIE_CHAT_HQ_MODEL_DISPLAY_NAME"
$PA_HQ_PLUS_MODEL_NAME_KEY = "AYFIE_CHAT_HQ_PLUS_MODEL_DISPLAY_NAME"

# Model deployment settings were explicitly stripped from docker/.env by the Saga 6->7 upgrade
# script (confirmed in index repo's TEMPLATE-upgrade-saga6-to-saga7.ps1, $PA_VARIABLES_TO_REMOVE) -
# models are configured through the Agent app's own System Settings wizard from Saga 7 onward, not
# via .env. Matches ConfigInspector's own major-version gate for this section.
$PA_MODEL_FIELDS_DROPPED_FROM_SAGA_MAJOR_VERSION = 7

################## LINGO INFO ##################

$LINGO_CONTAINER_NAME   = "ayfie-lingo"
$LINGO_STANDARD_LICENSE = "Lingo Standard"
$LINGO_GDPR_LICENSE     = "Lingo GDPR"

$LINGO_ENABLED_KEY      = "AYFIE_LINGO"
$LINGO_IMAGE_ID_KEY     = "AYFIE_LINGO_EXTRACTION_IMAGE_ID"
$LINGO_PII_LANGUAGE_KEY = "AYFIE_LINGO_EXTRACTION_PII_LANGUAGE_ID"
$LINGO_THREADS_KEY      = "AYFIE_LINGO_PIPELINE_POOL_SIZE"
$LINGO_RECYCLE_MEM_KEY  = "AYFIE_LINGO_RECYCLE_ON_MEMORY_THRESHOLD_IN_MB"
$LINGO_RECYCLE_RUNS_KEY = "AYFIE_LINGO_RECYCLE_AFTER_RUNS"
$LINGO_RECYCLE_TIME_KEY = "AYFIE_LINGO_RECYCLE_AFTER_PROCESSING_TIME_IN_SECONDS"

$LINGO_PII_LABEL = "pii"
$LINGO_LANGUAGES = @('da', 'en', 'fr', 'de', 'it', 'nb', 'pl', 'pt', 'es', 'sv')

################## TEMPORARY .ENV FILE CHANGES ##################

# Ayfie.Saga.zip is the original install bundle Saga itself keeps at the install root after
# install/update (index repo's docker-functions.ps1 falls back to a local ".\Ayfie.Saga*.zip" when
# updating offline) - its Saga/docker/.env is the pristine, as-shipped reference configuration this
# feature diffs the currently running .env against.
$SAGA_ZIP_FILE_NAME               = "Ayfie.Saga.zip"
$REFERENCE_DOT_ENV_RELATIVE_PATH  = "Saga\docker\.env"

# Rewritten by Saga's own tooling depending which optional add-ons (chat, report engine) are
# enabled, so it legitimately differs from the reference on every real installation - not a sign of
# an unexpected hand-edit the way any other modified variable would be.
$COMPOSE_FILE_KEY = "COMPOSE_FILE"

################## SCHEDULED RESTART ##################

$RESTART_TASK_NAME = "Restart-Saga"
$NO_SCHEDULED_TASK = "No scheduled restart"

################## FIREWALL OPENINGS ##################

$HTTPS_PORT = 443

# Sites Ayfie/Saga itself needs outbound access to (updates, Docker Hub, licensing/activation,
# auth). Not exhaustive of everything a given installation might need (e.g. customer-specific
# connector endpoints), just what the platform itself relies on regardless of customer.
$FIREWALL_OPENINGS = @(
    "https://go.microsoft.com",
    "https://www.powershellgallery.com",
    "https://onegetcdn.azureedge.net/providers/nuget-2.8.5.207.package.swidtag",
    "https://download.docker.com",
    "https://github.com",
    "https://raw.githubusercontent.com",
    "https://auth.docker.io/token",
    "https://cdn.auth0.com",
    "https://login.docker.com",
    "https://hub.docker.com",
    "https://docker.io",
    "https://activate.virtualworks.com",
    "https://login.microsoftonline.com"
)

# Either of these being reachable is an acceptable substitute for the other - reported separately
# from the main list since neither being reachable isn't necessarily a problem on its own.
$FIREWALL_OPENINGS_ALTERNATES = @(
    "https://psg-prod-centralus.azureedge.net/packages/microsoft.graph.2.24.0.nupkg",
    "https://psg-prod-eastus.azureedge.net/packages/microsoft.graph.2.24.0.nupkg"
)
