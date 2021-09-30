Install-Module -Name Intersight.PowerShell

# Modify KeyId and Path as needed for the desired account. 
# https://github.com/CiscoDevNet/intersight-powershell/blob/master/GettingStarted.md
#
$connect = @{
    BasePath = "https://intersight.com"
    ApiKeyId = "6155e2297564612d33fca3b4/6155e2297564612d33fca3b8/6155e3b47564612d30e377ed"
    ApiKeyFilePath = "F:\PowerShell\Intersight\SecretKey.txt" 
    HttpSingingHeader =  @("(request-target)", "Host", "Date", "Digest")
}
#Note - "HttpSingingHeader" is the correct syntax - the API has a typo (could be fixed at some point in the future and your scripts would need to be modified to correct the typo)
Set-IntersightConfiguration @connect
Get-IntersightConfiguration

#Get the List of Organizations
$OrgList = Get-IntersightOrganizationOrganization
#Get the OrganizationOrganization by Name
$OrgName = "Default"
$OrgByName = Get-IntersightOrganizationOrganization -Name $OrgName



