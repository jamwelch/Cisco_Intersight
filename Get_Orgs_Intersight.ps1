Install-Module -Name Intersight.PowerShell

# Modify API Key and Path to your secret key as needed for the desired account.
$APIKEY = "YOUREXTREMELYLONGAPIKEYGOESHERE"
$SECRETKEYPATH = "C:\PATH\TO\YOUR\SecretKey.txt"

$connect = @{
    BasePath = "https://intersight.com"
    ApiKeyId = $APIKEY
    ApiKeyFilePath = $SECRETKEYPATH
    HttpSingerHeader =  @("(request-target)", "Host", "Date", "Digest")
    # HttpSignerHeader =  @("(request-target)", "Host", "Date", "Digest")
    # Bug filed for this typo and will be fixed in next release.  
    # "HttpsignerHeader" should be used once the fix is in.
}

Set-IntersightConfiguration @connect
Get-IntersightConfiguration

#Get the List of Organizations
Get-IntersightOrganizationOrganization

#Get the Organization by Name - Change Org Name as desired
$OrgName = "Default"
$OrgByName = Get-IntersightOrganizationOrganization -Name $OrgName



