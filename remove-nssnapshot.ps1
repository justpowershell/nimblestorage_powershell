<#
   .SYNOPSIS
    Removes snapshots from Nimble array based on search criteria.

   .DESCRIPTION
    The four functions can be used in conjunction to remove orphaned snapshots (snapshots whose
    lifecycle is no longer being managed automatically and will not be removed without manual
    intervention). The script can also be used to remove snapshots older than a certain date,
    delete all snapshots in a volume, or delete a specific snapshot within a volume.

   .EXAMPLE
    #Remove all snapshots not created from the volume's current volume collection, possibly indicating an orphaned snapshot.
    get-nsvol | foreach { $_ | get-nssnapshot | where {$_.snap_collection_name -notlike "$($nsvol.volcoll_name)*"} | remove-nssnapshot }

    #Show all snapshots older than 7 days that would be removed without the -whatif parameter
    get-nsvol | foreach { $_ | get-nssnapshot | where {$_.creation_time -lt (convertto-epoch ((Get-Date).AddDays(-7)))} | remove-nssnapshot -whatif }

    #Remove all snapshots in a volume without a prompt, careful here.
    get-nsvol MyVol | get-nssnapshot | remove-nssnapshot -confirm:$false

    #Remove all snapshots in a volume without a prompt, careful here.
    get-nsvol MyVol | get-nssnapshot | remove-nssnapshot -confirm:$false

    #Remove any snapshots in a volume with 'manual' in the description with vervose results
    get-nsvol MyVol | get-nssnapshot | where {$_.description -like "*manual*"} | remove-nssnapshot -verbose
    
   
   .NOTES
    Name            : remove-nssnapshots.ps1
    Author          : Paul Sabin
    Lastedit        : 10/17/2016 11:03:01

   .INPUTS
    none

   .OUTPUTS
    none

   .LINK
    https://devgit01.bakerbotts.net/it_oi/powershell_scripts
#>

#Requires -Version 2.0 

$nsarray = Read-Host "Enter DNS Name for array"  # Replace with your array name

$nscreds = Get-Credential # See http://social.technet.microsoft.com/wiki/contents/articles/4546.working-with-passwords-secure-strings-and-credentials-in-windows-powershell.aspx on how to store credentials in script.
$nsuser = $nscreds.UserName
$nspass = $nscreds.GetNetworkCredential().Password

function get-token {

    $username = $nsuser
    $password = $nspass

    $data = @{
        username = $username
	    password = $password
    }

    $body = convertto-json (@{ data = $data })

    $uri = "https://" + $array + ":5392/v1/tokens"
    $token = Invoke-RestMethod -Uri $uri -Method Post -Body $body
    $global:token = $token.data.session_token
}

function get-nsvol {
    Param(
        [Parameter(Mandatory=$False,
        ValueFromPipeLine=$True)]
        [string]$name
    )
    get-token 
    $header = @{ "X-Auth-Token" = $token }
    if ($name){
        $uri = "https://" + $array + ":5392/v1/volumes?name=$name"
    } else {
        $uri = "https://" + $array + ":5392/v1/volumes"
    }        
    $volume_list = Invoke-RestMethod -Uri $uri -Method Get -Header $header
    $vol_array = @()
    foreach ($volume_id in $volume_list.data.id){
	    $uri = "https://" + $array + ":5392/v1/volumes/" + $volume_id
	    $volume = Invoke-RestMethod -Uri $uri -Method Get -Header $header
	    #write-host $volume.data.name :     $volume.data.id
	    $vol_array += $volume.data
    }
    return $vol_array
}

function get-nssnapshot {
    Param(
        [Parameter(Position=0,
        Mandatory=$True,
        ValueFromPipeLine=$True,  
        ValueFromPipeLineByPropertyName=$True)]
        [string]$id
    )
    get-token
    $header = @{ "X-Auth-Token" = $token }
    $uri = "https://" + $array + ":5392/v1/snapshots/detail/?vol_id=$id"
    $nssnapshots = @()
    $nssnapshots += Invoke-RestMethod -Uri $uri -Method Get -Header $header | select -ExpandProperty data
    return $nssnapshots
}

function remove-nssnapshot {
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact="High")]
    Param(
        [Parameter(Mandatory=$True,
        ValueFromPipeLine=$True,  
        ValueFromPipeLineByPropertyName=$True)]
        [string]$id,
        [Parameter(Mandatory=$False,
        ValueFromPipeLine=$True,  
        ValueFromPipeLineByPropertyName=$True)]
        [string]$name="Unknown"
    )
    begin {
        Write-Verbose "$(get-date) starting remove-nssnapshot"
    } process { 
        Write-Verbose "id = $id"
        Write-Verbose "name=$name"

        if ($pscmdlet.shouldprocess($name)) {        
            write-host "Removing `"$name`""
            get-token
            $header = @{ "X-Auth-Token" = $token }
            $uri = "https://" + $array + ":5392/v1/snapshots/$id"
            Invoke-RestMethod -Uri $uri -Method Delete -Header $header
        }
    } end {
        Write-Verbose "$(get-date) ending remove-snapshot"
    }
}
 
function convertto-epoch {
    param (
        [Parameter(Mandatory=$True,
        ValueFromPipeLine=$True)]
        [datetime]$date
    )
    [datetime]$origin = '1970-01-01 00:00:00'
    [int]$return = $date - $origin | select -ExpandProperty TotalSeconds
    return $return
}

