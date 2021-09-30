Install-Module -Name Intersight.PowerShell

$connect = @{
    BasePath = "https://intersight.com"
    ApiKeyId = "6155e2297564612d33fca3b4/6155e2297564612d33fca3b8/6155e3b47564612d30e377ed"
    ApiKeyFilePath = "secrectKey.txt" 
    HttpSignerHeader =  @("(request-target)", "Host", "Date", "Digest")
}

Set-IntersightConfiguration @connect
Get-IntersightConfiguration