Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-SolutionName {
    param([string]$Name)
    if ($Name -cnotmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Provide a valid solution unique name: letters, digits and underscores.'
    }
}

function Assert-PrivateRepositoryMetadata {
    param([object]$Repository, [string]$ExpectedRepositoryId, [string]$ExpectedProjectId)
    if ([string]$Repository.id -ine $ExpectedRepositoryId -or
        [string]$Repository.project.id -ine $ExpectedProjectId -or
        [string]$Repository.project.visibility -cne 'private') {
        throw 'The runtime repository must be the expected private Azure Repos repository.'
    }
}

function Assert-PrivateRuntimeRepository {
    if ($env:BUILD_REPOSITORY_PROVIDER -cne 'TfsGit' -or $env:BUILD_SOURCEBRANCH -cne 'refs/heads/main') {
        throw 'This producer requires private Azure Repos on main. Copy the sample to that repository first.'
    }
    foreach ($name in 'SYSTEM_ACCESSTOKEN','SYSTEM_COLLECTIONURI','SYSTEM_TEAMPROJECTID','BUILD_REPOSITORY_ID') {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            throw "Missing runtime variable: $name"
        }
    }
    $collection = [uri]$env:SYSTEM_COLLECTIONURI
    if ($collection.Scheme -ne 'https' -or $collection.UserInfo -or $collection.Query -or
        $collection.Fragment -or -not $collection.IsDefaultPort -or
        ($collection.Host -ne 'dev.azure.com' -and $collection.Host -notmatch '^[a-z0-9-]+\.visualstudio\.com$')) {
        throw 'Expected an Azure DevOps HTTPS collection URL.'
    }
    $project = ([guid]$env:SYSTEM_TEAMPROJECTID).ToString()
    $repository = ([guid]$env:BUILD_REPOSITORY_ID).ToString()
    try {
        $metadata = Invoke-RestMethod -Uri "$($collection.AbsoluteUri.TrimEnd('/'))/$project/_apis/git/repositories/${repository}?api-version=7.1" `
            -Headers @{Authorization="Bearer $env:SYSTEM_ACCESSTOKEN"} -MaximumRedirection 0 -TimeoutSec 60
    }
    catch { throw 'Unable to verify private Azure Repos visibility. No export or commit is authorized.' }
    Assert-PrivateRepositoryMetadata $metadata $repository $project
}

function Assert-TextPrivacy {
    param([string]$Text)
    $rules = [ordered]@{
        'email address' = '(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
        'private key' = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
        'access token' = '(?i)(?:gh[pousr]_[a-z0-9]{25,}|github_pat_[a-z0-9_]{25,}|eyJ[a-z0-9_-]{15,}\.[a-z0-9_-]{15,}\.[a-z0-9_-]{15,})'
        'signed URL' = '(?i)[?&](?:amp;)?sig=[a-z0-9%+/=_-]{12,}'
        'user profile path' = '(?i)(?:[a-z]:[\\/]+Users[\\/]+[^\\/\s<>]+|/home/[^/\s<>]+)'
        'tenant or environment endpoint' = '(?i)https?://[a-z0-9.-]+\.(?:dynamics\.com|onmicrosoft\.com|sharepoint\.com)|https?://(?:make\.powerapps\.com|make\.powerautomate\.com|copilotstudio\.microsoft\.com)/environments/'
        'literal secret setting' = '(?im)(?:client[_-]?secret|password|api[_-]?key|access[_-]?token)\s*["'']?\s*[:=]\s*["''][a-z0-9/+_=.-]{12,}["'']'
    }
    foreach ($rule in $rules.GetEnumerator()) {
        if ($Text -match $rule.Value) {
            throw "Privacy check rejected a possible $($rule.Key). Review locally; matched values are not logged."
        }
    }
}

function Get-SelectedSourcePaths {
    param([string]$SolutionName)
    Assert-SolutionName $SolutionName
    @("Samples/AzureDevOps/Solutions/$SolutionName", "Samples/AzureDevOps/Settings/$SolutionName.json")
}

function Assert-SourceFilesPrivacy {
    param([string]$Root, [string]$SolutionName)
    $paths = @(Get-SelectedSourcePaths $SolutionName)
    $files = @()
    foreach ($relative in $paths) {
        $path = Join-Path $Root $relative
        $item = Get-Item -LiteralPath $path
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source root cannot be a symlink or reparse point.' }
        if ($item.PSIsContainer) {
            $children = @(Get-ChildItem -LiteralPath $path -Recurse -Force)
            if (@($children | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
                throw 'Source cannot contain symlinks or reparse points.'
            }
            $files += @($children | Where-Object { -not $_.PSIsContainer })
        } else { $files += $item }
    }
    if (-not $files.Count) { throw 'No selected source files to inspect.' }
    foreach ($file in $files) {
        Assert-TextPrivacy ([IO.Path]::GetRelativePath($Root,$file.FullName))
        if ($file.Extension -notin @('.xml','.json','.yaml','.yml','.txt','.md','.csv','.js','.css','.html','.resx','.svg','')) {
            throw 'Selected source includes a binary or unsupported file. Review and extend the scanner before using this sample.'
        }
        if ($file.Length -gt 10MB) { throw 'Selected source exceeds the per-file privacy inspection limit.' }
        try { $text = [IO.File]::ReadAllText($file.FullName, [Text.UTF8Encoding]::new($false,$true)) }
        catch { throw 'Source could not be decoded as UTF-8 text. Review privately; values were withheld.' }
        if ($text.Contains([char]0)) { throw 'Selected source includes binary data; review locally.' }
        Assert-TextPrivacy $text
    }
}

function Invoke-CheckedGit {
    param([string]$Root, [string[]]$Arguments)
    $output = & git -C $Root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Git operation failed. Review the private working copy; command output was withheld.' }
    $output
}

function Add-SelectedSource {
    param([string]$Root, [string]$SolutionName)
    $paths = @(Get-SelectedSourcePaths $SolutionName)
    $staged = @(Invoke-CheckedGit $Root @('diff','--cached','--name-only'))
    if ($staged.Count) { throw 'The index already contains staged files. Refusing to include unrelated work.' }
    Assert-SourceFilesPrivacy $Root $SolutionName
    $null = Invoke-CheckedGit $Root (@('add','--') + $paths)
    $staged = @(Invoke-CheckedGit $Root @('diff','--cached','--name-only'))
    foreach ($path in $staged) {
        if ($path -cne $paths[1] -and -not $path.StartsWith($paths[0] + '/', [StringComparison]::Ordinal)) {
            throw 'Unexpected staged file. No commit was made.'
        }
    }
    $staged
}

Export-ModuleMember -Function Assert-SolutionName,Assert-PrivateRepositoryMetadata,Assert-PrivateRuntimeRepository,Assert-TextPrivacy,Assert-SourceFilesPrivacy,Get-SelectedSourcePaths,Invoke-CheckedGit,Add-SelectedSource
