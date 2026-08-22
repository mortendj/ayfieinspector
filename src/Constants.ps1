################## VERSION ##################

# Named distinctly from Winspect's own $SCRIPT_VERSION/$SCRIPT_NAME (Constants.ps1) - Invoke-
# AyfieInspector.ps1 dot-sources Winspect's Constants.ps1 too, and those names are already claimed
# there.
$AYFIE_INSPECTOR_VERSION = "0.1.0"
$AYFIE_INSPECTOR_NAME    = "AyfieInspector"

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
