Install-Module -Name Intersight.PowerShell
$APIKEY = "YOUREXTREMELYLONGAPIKEYGOESHERE"
$SECRETKEYPATH = "C:\PATH\TO\YOUR\SecretKey.txt"

$connect = @{
    BasePath = "https://intersight.com"
    ApiKeyId = $APIKEY
    ApiKeyFilePath = $SECRETKEYPATH
    HttpSignerHeader =  @("(request-target)", "Host", "Date", "Digest")
}

Set-IntersightConfiguration @connect
Get-IntersightConfiguration
