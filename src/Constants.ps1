################## VERSION ##################

# Named distinctly from Winspect's own $SCRIPT_VERSION/$SCRIPT_NAME (Constants.ps1) - Invoke-
# AyfieInspector.ps1 dot-sources Winspect's Constants.ps1 too, and those names are already claimed
# there.
$AYFIE_INSPECTOR_VERSION           = "0.2.1"
$AYFIE_INSPECTOR_VERSION_TIMESTAMP = "2026-08-22"
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
