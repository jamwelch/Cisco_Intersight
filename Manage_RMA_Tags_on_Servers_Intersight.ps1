<# Author: James Welch
Contact: jamwelch@cisco.com
Summary:  This script will add and change the RMA tags for server objects in intersight.
          Using the RMA tags on server objects in Intersight is NOT yet supported by Cisco, 
          so do not use this script unless explicitly prescribed by a Cisco engineer.
          
          The script does not delete any tags including pre-existing server tags or RMA tags not listed in the csv file.
          
          The script assumes you have a csv formatted file containing 2 columns.
          Find the file "example.csv" in this repository.
          The file should be formatted in this fashion:
          
          serial_number;rma_email
          SERIAl1;name@domain.com
          SERIAL1;name@domain.com
          Use the same headings as above in your data file.
          Make sure the serial numbers match the server object you intend to tag 
          with a specific e-mail address.  #>
          
Install-Module -Name Intersight.PowerShell
# Replace string in quotes with your API key in quotes
$APIKEY = "YOUREXTREMELYLONGAPIKEYGOESHERE"
# Replace with correct path and file name for your secret key - keep quotes in place
$SECRETKEYPATH = "C:\PATH\TO\YOUR\SecretKey.txt"

# Modify to match the name of your csv input file
# File must use a semicolon for the delimiter
# Separate multiple e-mail addresses for a single tag using a comma
$InputFile = 'example.csv'

$connect = @{
    BasePath = "https://intersight.com"
    ApiKeyId = $APIKEY
    ApiKeyFilePath = $SECRETKEYPATH
    HttpSigningHeader =  @("(request-target)", "Host", "Date", "Digest")
}

Set-IntersightConfiguration @connect
Get-IntersightConfiguration
$RMAKey = "AutoRMAEmail"
$ServerTagEmail = "test"
$EMAIL = 'x'
$ChangeRMATag = $True
$RMATagGood = $True

# Open data file and read each line performing update function for each line
$Input_file = Import-Csv -Path $InputFile -Delimiter ";"
$Input_file | ForEach-Object {
    $SN = $_.serial_number
    $EMAIL = $_.rma_email
    Write-Output "`n"
    Write-Output "Server with serial number $SN should get RMA tag for $EMAIL"
    
    # Filter through the list of all servers to find the ones listed in the file
    $Server = Get-IntersightComputePhysicalSummary | Where-Object {$_.Serial -eq $SN}
    $ServerMoid = $Server.Moid
    $ServerDn = $Server.Dn
    $ServerSN = $Server.Serial
    $ServerBlade = $ServerDn.contains("blade")
    $ServerRack = $Serverdn.contains("rack")
    if ($ServerBlade){
        Write-Output "$ServerDn is a blade"
    }
    if ($ServerRack){Write-Output "$ServerDn is a rack unit"
    }
    $ServerTags = $Server.Tags

    #Check if Tag is an RMA Tag
    $NoTag = $True
    if ($ServerTags | Where-Object {$_.Key -eq $RMAKey}){
        $NoTag = $False
    }
    $ServerTag = $ServerTags | Where-Object "Key" -eq $RMAKey
    $ServerTagEmail = $ServerTag.Value
    $RMATagGood = $ServerTagEmail -eq $EMAIL
    $ChangeRMATag = $ServerTagEmail -ne $EMAIL
    $OtherTags = $ServerTags | Where-Object "Key" -ne $RMAKey
    $NoOtherTag = $True
    if ($OtherTags | Where-Object {$_.Key -ne $RMAKey}){
        $NoOtherTag = $False
    }
    $TagCount = ($OtherTags).count
    if (-not($NoTag))
    {
        Write-Output "RMA tag detected for $ServerDn"
        Write-Output "Tag detected with value of $ServerTagEmail"
        if($RMATagGood)
        {
            Write-Output "The RMA tag for $ServerDn does not need to be changed"
            Write-Output "$ServerTagEmail and $EMAIL are the same"
        }
        if($ChangeRMATag)
        {
            Write-Output "The RMA tag for $ServerDn needs to be changed"
            Write-Output "It needs to be changed from $ServerTagEmail to $EMAIL"
            Write-Output "Proceeding with modifying RMA tag for $ServerSN"
            $TotalMoTags = @()
            $TotalMoTags += Initialize-IntersightMoTag -Key "AutoRMAEmail" -Value $EMAIL
            if(-not($NoOtherTag))
            {
                $i = $TagCount - 1
                DO {
                    $OtherTag = $OtherTags[$i]
                    $i = $i - 1
                    $OtherTagsKey = $OtherTag.Key
                    $OtherTagsValue = $OtherTag.Value
                    $TotalMoTags += Initialize-IntersightMoTag -Key $OtherTagsKey -Value $OtherTagsValue
                } Until ($i -lt 0)
            }
            if($ServerBlade){
                Set-IntersightComputeBlade -Moid $ServerMoid -Tags $TotalMoTags | out-null
            }
            else{
                Set-IntersightComputeRackUnit -Moid $ServerMoid -Tags $TotalMoTags | out-null
            }
        }
    }
    if ($NoTag)
    {
        Write-Output "$ServerDn does not have an RMA tag"
        Write-Output "Proceeding with adding new RMA tag for $ServerSN"
        $TotalMoTags = @()
        $TotalMoTags += Initialize-IntersightMoTag -Key "AutoRMAEmail" -Value $EMAIL
        if(-not($NoOtherTag))
        {
            $i = $TagCount - 1
            DO {
                $OtherTag = $OtherTags[$i]
                $i = $i - 1
                $OtherTagsKey = $OtherTag.Key
                $OtherTagsValue = $OtherTag.Value
                $TotalMoTags += Initialize-IntersightMoTag -Key $OtherTagsKey -Value $OtherTagsValue
            } Until ($i -lt 0)
        }
        # Check if server is a blade or a rack unit
        if($ServerBlade){
            Set-IntersightComputeBlade -Moid $ServerMoid -Tags $TotalMoTags | out-null
        }
        else{
            Set-IntersightComputeRackUnit -Moid $ServerMoid -Tags $TotalMoTags | out-null
        }
    }
}
