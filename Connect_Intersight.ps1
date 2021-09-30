Install-Module -Name Intersight.PowerShell
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
