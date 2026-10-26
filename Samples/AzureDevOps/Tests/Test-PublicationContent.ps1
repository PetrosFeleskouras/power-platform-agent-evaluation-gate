[CmdletBinding()]
param(
    [string]$BaseRef = 'origin/main'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot))
$changes=@(git -C $root diff --cached --name-status $BaseRef)
if($LASTEXITCODE-ne 0){throw 'Cannot inspect staged publication changes.'}
if(-not $changes.Count){throw 'Stage the new publication files before running this check.'}
$failures=@()
foreach($entry in $changes) {
    $parts=$entry -split "`t"
    if($parts[0]-cne'A'){throw 'This publication must be additive. An existing asset would be modified or deleted.'}
    $path=$parts[1]
    if($path-match'(^|/)(?:\.local|\.mcs|node_modules)/|\.zip$|\.local\.json$|\.log$|\.png$|\.pptx$') {
        throw 'Private, binary or generated file is staged; publication blocked.'
    }
    $text=(git -C $root show ":$path") -join "`n"
    if($LASTEXITCODE-ne 0){throw 'Cannot read a staged blob.'}
    foreach($m in [regex]::Matches($text,'(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}')) {
        if(-not$m.Value.EndsWith('@example.invalid',[StringComparison]::OrdinalIgnoreCase)) {
            $failures+="$path : nonsynthetic email"
        }
    }
    foreach($m in [regex]::Matches($text,'(?i)\b[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\b')) {
        if($m.Value.Replace('-','')-notmatch'^(.)\1{31}$'){$failures+="$path : nonsynthetic GUID"}
    }
    if($text-match'(?i)shared-microsoftcopi-[0-9a-f]{8}-|[?&]sig=[a-z0-9%+/=_-]{12,}|github_pat_[a-z0-9_]{25,}|gh[pousr]_[a-z0-9]{25,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----') {
        $failures+="$path : operational binding or secret pattern"
    }
    foreach($m in [regex]::Matches($text,'(?i)https?://[a-z0-9.-]+\.(?:dynamics\.com|onmicrosoft\.com|sharepoint\.com)')) {
        if($m.Value-cne'https://synthetic.crm.dynamics.com'){$failures+="$path : environment endpoint"}
    }
}
if($failures.Count){$failures|Write-Warning;throw 'Publication-content check failed. Values were withheld.'}
Write-Host "Reviewed $($changes.Count) staged added files: no known instance identifiers, personal emails, secrets or generated artifacts detected."
Write-Host 'Human review remains required for names, embedded content and identifiers not covered by these patterns.'
