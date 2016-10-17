# nimblestorage_powershell

Having written PowerShell scripts for managing other arrays, I decided to retrofit those scripts for use on my shiny new Nimble Arrays.
In order to minimize work, I will replace my existing functions to use the REST API features on the latest Nimble OS.

# Add-NSInitiators.ps1
This script will ask for the vCenter for which you will add the Nimble Array. The script will then create Initiator Groups on the
Nimble Array for each host and will also create Initiator Groups for each of your vCenter clusters.

# Remove-Nssnapshot.ps1
The four functions can be used in conjunction to remove orphaned snapshots (snapshots whose lifecycle is no longer being managed automatically and will not be removed without manual intervention). The script can also be used to remove snapshots older than a certain date, delete all snapshots in a volume, or delete a specific snapshot within a volume.
