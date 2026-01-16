<#
.SYNOPSIS
    Clean up the AI Adversary Lab environment
.DESCRIPTION
    Deletes all Azure resources created by Deploy-Lab.ps1
.EXAMPLE
    ./Cleanup-Lab.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║           AI ADVERSARY LAB - CLEANUP                          ║" -ForegroundColor Red
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "lab_config.json"

if (-not (Test-Path $configPath)) {
    Write-Host "[!] Config file not found: $configPath" -ForegroundColor Red
    Write-Host "    Nothing to clean up." -ForegroundColor Gray
    exit 0
}

$config = Get-Content $configPath | ConvertFrom-Json

Write-Host "This will delete:" -ForegroundColor Yellow
Write-Host "  • Resource Group: $($config.ResourceGroup)"
Write-Host "  • All resources within the group"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Are you sure? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Cancelled." -ForegroundColor Gray
        exit 0
    }
}

Write-Host ""
Write-Host "Deleting resource group..." -ForegroundColor Cyan
az group delete --name $config.ResourceGroup --yes --no-wait

Write-Host ""
Write-Host "✓ Deletion initiated (running in background)" -ForegroundColor Green
Write-Host ""
Write-Host "The resource group will be deleted in a few minutes." -ForegroundColor Gray
Write-Host "You can check status with:" -ForegroundColor Gray
Write-Host "  az group show --name $($config.ResourceGroup) --query properties.provisioningState" -ForegroundColor White
Write-Host ""

# Remove config file
Remove-Item $configPath -Force -ErrorAction SilentlyContinue
Write-Host "✓ Config file removed" -ForegroundColor Green
Write-Host ""
