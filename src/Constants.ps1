################## VERSION ##################

# Named distinctly from Winspect's own $SCRIPT_VERSION/$SCRIPT_NAME (Constants.ps1) - Invoke-
# AyfieInspector.ps1 dot-sources Winspect's Constants.ps1 too, and those names are already claimed
# there.
$AYFIE_INSPECTOR_VERSION           = "0.7.0"
$AYFIE_INSPECTOR_VERSION_TIMESTAMP = "2026-08-26"
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
