<#
   .SYNOPSIS
    Add-NSInitiators.ps1

   .DESCRIPTION
    The script scans your vCenter ESXi hosts and compares determines if the WWPN's exist in similar named Nimble Initiator groups.
    If the IG or the WWPN does not exist, the script will create them using Nimble's RESTful API.

   .EXAMPLE
    Example-
    Example- Add-NSInitiators.ps1

   .NOTES
    Name            : Add-NSInitiators.ps1
    Author          : Paul Sabin @justpaul
    Lastedit        : 05/18/2016

   .INPUTS
    vCenter name and credentials
    Nimble storage name and credentials

   .LINK
    https://github.com/justpowershell/nimblestorage_powershell/blob/master/Add-NSInitiators.ps1
#>

$nimblearray = read-host "Enter Nimble array DNS name"
$nimblecred = Get-Credential -Message "Enter credentials for Nimble Array" -UserName "admin"
$vcenter = read-host "Enter vCenter server name"
$vcentercred = Get-Credential -Message "Enter credentials for vCenter server"

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

function get-vmhba {
    param ($esx)
    Write-Verbose "Host: $esx"
    $hbas = Get-VMHostHba -VMHost $esx -Type FibreChannel
    $results = @()
    foreach ($hba in $hbas){
        $result = "" | select Device,Model,WWPN
        $result.Device = $hba.Device
        $result.Model = $hba.model
        $result.WWPN = "{0:x}" -f $hba.PortWorldWideName
        $results += $result
    }
    return $results
}

function get-nimbletoken {
    param ([string]$array=$nimblearray,[string]$user=$nimbleusername,[string]$password=$nimblepassword)
    $data = @{
        username = $nimblecred.UserName
	    password = $nimblecred.GetNetworkCredential().password
    }

    $body = convertto-json (@{ data = $data })

    $uri = "https://" + $array + ":5392/v1/tokens"
    $token = Invoke-RestMethod -Uri $uri -Method Post -Body $body
    $token = $token.data.session_token
    return $token
}

function get-nimbleinitiatorgroups {
    param (
        [string]$array=$nimblearray,
        [string]$token=$(get-nimbletoken)
    )
    $uri = "https://" + $array + ":5392/v1/initiator_groups/detail"
    $header = @{ "X-Auth-Token" = $token }
    $igs = Invoke-RestMethod -Uri $uri -Method Get -Headers $header
    $igs = $igs.data
    return $igs
}

function format-wwpn {
    param([string]$wwpn)
    ForEach ($position in 14,12,10,8,6,4,2) {$wwpn = $wwpn.Insert($position,":")}
    return ($wwpn).ToUpper() # fixes a known bug in Nimble REST API Pre-3.4
}

function update-nimbleigs {
    Write-Verbose "update-nimbleigs"
    $global:igs = get-nimbleinitiatorgroups
    $global:ignames = @($igs.name)
}
 
function new-nimbleinitiatorgroup {
    [CmdletBinding()]
    param (
        [string]$array=$nimblearray,
        [string]$token=$(get-nimbletoken),
        [string]$igname,
        [string]$description=""
    )
    Write-Verbose "new-nimbleinitiatorgroup $array $token $igname $description"
    $data = "" | select name,description,access_protocol
    $data.name = $igname
    $data.access_protocol = "fc"
    $data.description = $description

    $body = convertto-json (@{ data = $data })
    Write-Verbose $body
    $header = @{ "X-Auth-Token" = $token }
    $uri = "https://" + $array + ":5392/v1/initiator_groups"
    $result = Invoke-RestMethod -Uri $uri -Method Post -Body $body -Header $header
    update-nimbleigs
    return $result.data
}

function add-nimbleinitiator{
    [CmdletBinding()]
    param (
        [string]$array=$nimblearray,
        [string]$token=$(get-nimbletoken),
        [string]$igname=$igname,
        [string]$vmhostname=$vmhostname
    )

    Write-Verbose "add-nimbleinitiator $array $token $igname $vmhostname"

    $ig = $igs | where {$_.name -eq $igname}
    $igid = $ig.id
    if (!($ig.id)){
        Write-Error "Could not determine initiator group ID"
        Return
    }
    $igfcinitiators = @($ig.fc_initiators)
    
    $vmhbas = get-vmhba -esx $vmhostname
    
    $results = @()

    foreach ($vmhba in $vmhbas){
        if ($igfcinitiators.wwpn -notcontains $(format-wwpn $vmhba.WWPN)){
            $data = "" | select initiator_group_id,access_protocol,wwpn
            $data.initiator_group_id= $igid
            $data.access_protocol = "fc"
            # $data.alias = ("$($vmhostname.split(".")[0])-$($vmhba.Device)").ToUpper()
            $data.wwpn = format-wwpn $vmhba.WWPN

            $body = convertto-json (@{ data = $data })
            Write-Verbose $body
            $header = @{ "X-Auth-Token" = $token }
            $uri = "https://" + $array + ":5392/v1/initiators"
            $results += Invoke-RestMethod -Uri $uri -Method Post -Body $body -Header $header
            update-nimbleigs
        }
    }
    return $results.data
}

if (!(connect-viserver $vcenter -Credential $vcentercred)){
    Write-Host "There was an error connecting to the vCenter server `"$vcenter`""
    Exit 99
}

if (!(get-nimbletoken)){
    Write-Host "There was an error connecting to the Nimble array`"$nimblearray`""
    Exit 99
}

update-nimbleigs

$vmclusters = @(Get-Cluster | sort Name)

Foreach ($vmcluster in $vmclusters){
    $clustername = $vmcluster.Name
    write-host $clustername -ForegroundColor "Green"
    $igclustername = $("IG-$($clustername)").ToUpper()
    if ($ignames -notcontains $igclustername){
        new-nimbleinitiatorgroup -igname $igclustername
    }
    $vmhosts = @($vmcluster | Get-VMHost | sort Name)
    foreach ($vmhost in $vmhosts){
        $vmhostname = $vmhost.Name
        Write-Host "* $vmhostname"
        add-nimbleinitiator -igname $igclustername -vmhostname $vmhostname
        $ighostname = $("IG-$($vmhostname.split(".")[0])").ToUpper()
        if ($ignames -notcontains $ighostname){
            new-nimbleinitiatorgroup -igname $ighostname
        }
        add-nimbleinitiator -igname $ighostname -vmhostname $vmhostname
    }
}
