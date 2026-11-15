# Downloads the newest successful BetterBoard.ipa from GitHub Actions into build\
$ErrorActionPreference = 'Stop'
$repo = 'Leisurp/BetterBoard'

$runId = gh run list --repo $repo --workflow build.yml --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId'
if (-not $runId) { throw 'No successful build found yet.' }

$out = Join-Path $PSScriptRoot '..\build'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
gh run download $runId --repo $repo --name BetterBoard-ipa --dir $out

$ipa = Join-Path (Resolve-Path $out) 'BetterBoard.ipa'
Write-Host "Ready: $ipa"
