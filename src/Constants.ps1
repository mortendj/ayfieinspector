################## VERSION ##################

# Named distinctly from Winspect's own $SCRIPT_VERSION/$SCRIPT_NAME (Constants.ps1) - Invoke-
# AyfieInspector.ps1 dot-sources Winspect's Constants.ps1 too, and those names are already claimed
# there.
$AYFIE_INSPECTOR_VERSION           = "0.15.0"
$AYFIE_INSPECTOR_VERSION_TIMESTAMP = "2026-08-28"
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
$BRANDING_KEY                 = "AYFIE_SAGA_BRANDING_KEY"
$GIT_VERSION_RELATIVE_PATH    = "git.version"

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
