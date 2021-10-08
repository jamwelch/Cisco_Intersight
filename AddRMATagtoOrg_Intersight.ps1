Install-Module -Name Intersight.PowerShell
$APIKEY = "YOUREXTREMELYLONGAPIKEYGOESHERE"
$SECRETKEYPATH = "C:\PATH\TO\YOUR\SecretKey.txt"

$connect = @{
    BasePath = "https://intersight.com"
    ApiKeyId = $APIKEY
    ApiKeyFilePath = $SECRETKEYPATH
    HttpSingingHeader =  @("(request-target)", "Host", "Date", "Digest")
    # HttpSignerHeader =  @("(request-target)", "Host", "Date", "Digest")
    # Bug filed for this typo and will be fixed in next release.  
    # "HttpsignerHeader" should be used once the fix is in.
}

Set-IntersightConfiguration @connect
Get-IntersightConfiguration


$NewOrgName = Read-Host -Prompt "Enter the name of the organization"
$NewEmail = Read-Host -Prompt "Enter the email address that will receive AutoRMA notifications for this organization. Separate multiple e-mail addresses with a comma and no spaces. Please note that existing tags for this organization will be overwritten by this one."
$org = Get-IntersightOrganizationOrganization -Name $NewOrgName


#Add tags for automated RMA per org. Separate multiple e-mail addresses by a comma i.e. "joe@somedomain.com,sue@somedomain.com"
#Note - the email address(s) in here need to be correlative to a CCO Account
#Previous values will be overwritten
$NewTag = Initialize-IntersightMoTag -Key "AutoRMAEmail" -Value $NewEmail


$org | Set-IntersightOrganizationOrganization -Name $NewOrgName -Tags $NewTag

