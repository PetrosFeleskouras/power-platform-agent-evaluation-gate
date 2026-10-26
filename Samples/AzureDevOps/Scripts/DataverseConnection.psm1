Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-DeploymentDataverse {
    param([string]$Url, [string]$ClientId, [string]$ClientSecret)
    $uri = [uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
        -not $uri.IsDefaultPort -or $uri.AbsolutePath -ne '/') { throw 'Expected a Dataverse HTTPS root URL.' }
    if ([string]::IsNullOrWhiteSpace($ClientId) -or [string]::IsNullOrWhiteSpace($ClientSecret)) {
        throw 'A service-connection application ID and secret are required.'
    }
    try {
        if (-not (Get-Module -ListAvailable -Name Rnwood.Dataverse.Data.PowerShell | Where-Object Version -EQ '1.1.3')) {
            Install-Module Rnwood.Dataverse.Data.PowerShell -Scope CurrentUser -Force -AllowClobber -RequiredVersion 1.1.3 -Repository PSGallery *> $null
        }
        Import-Module Rnwood.Dataverse.Data.PowerShell -RequiredVersion 1.1.3 -ErrorAction Stop
        Get-DataverseConnection -Url $Url -ClientId $ClientId -ClientSecret $ClientSecret
    }
    catch { throw 'Dataverse connection failed. Verify the service connection; credential-bearing details were withheld.' }
}

function Get-NextSolutionVersion {
    param([version]$Current,[version]$Committed,[bool]$IncrementBuild=$true,[bool]$IncrementRevision=$false)
    if ($null -eq $Current -or $IncrementBuild -eq $IncrementRevision) {
        throw 'A current version and exactly one increment mode are required.'
    }
    $base=if($null -ne $Committed -and $Committed -gt $Current){$Committed}else{$Current}
    $build=[math]::Max(0,$base.Build)
    $revision=[math]::Max(0,$base.Revision)
    if($IncrementBuild){$build++;$revision=0}else{$revision++}
    "$($base.Major).$($base.Minor).$build.$revision"
}

Export-ModuleMember -Function Connect-DeploymentDataverse,Get-NextSolutionVersion
