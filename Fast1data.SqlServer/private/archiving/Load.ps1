using module ./ArchivingModel.psm1

# Root dot-sources this declaration only after SqlClient bootstrap completes.
# This makes model types available to the subsequently loaded archiving adapter.
