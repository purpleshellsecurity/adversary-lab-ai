<#
.SYNOPSIS
    Deploy the AI Adversary Lab environment
.DESCRIPTION
    Creates Azure AI Services, logging proxy, and Log Analytics workspace.
.EXAMPLE
    ./Deploy-Lab.ps1
    ./Deploy-Lab.ps1 -ResourceGroupName "my-lab-rg" -Location "eastus"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory = $false)]
    [string]$Suffix
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           AI ADVERSARY LAB - DEPLOYMENT                       ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Generate suffix if not provided
if (-not $Suffix) {
    $Suffix = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
}

if (-not $ResourceGroupName) {
    $ResourceGroupName = "rg-ai-adversary-$Suffix"
}

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $ResourceGroupName"
Write-Host "  Location: $Location"
Write-Host "  Suffix: $Suffix"
Write-Host ""

# Check Azure CLI login
Write-Host "[1/6] Checking Azure connection..." -ForegroundColor Cyan
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Not logged in. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# Create resource group
Write-Host "[2/6] Creating resource group..." -ForegroundColor Cyan
az group create --name $ResourceGroupName --location $Location --output none
Write-Host "  ✓ Resource group: $ResourceGroupName" -ForegroundColor Green

# Create Log Analytics workspace
Write-Host "[3/6] Creating Log Analytics workspace..." -ForegroundColor Cyan
$workspaceName = "law-ailab-$Suffix"
az monitor log-analytics workspace create `
    --resource-group $ResourceGroupName `
    --workspace-name $workspaceName `
    --location $Location `
    --output none

$workspaceId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroupName `
    --workspace-name $workspaceName `
    --query customerId -o tsv

$workspaceKey = az monitor log-analytics workspace get-shared-keys `
    --resource-group $ResourceGroupName `
    --workspace-name $workspaceName `
    --query primarySharedKey -o tsv

Write-Host "  ✓ Workspace: $workspaceName" -ForegroundColor Green

# Create Azure OpenAI resource
Write-Host "[4/6] Creating Azure AI Services..." -ForegroundColor Cyan
$openaiName = "ai-adversary-$Suffix"

az cognitiveservices account create `
    --name $openaiName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --kind "OpenAI" `
    --sku "S0" `
    --custom-domain $openaiName `
    --output none

# Get endpoint and key
$openaiEndpoint = az cognitiveservices account show `
    --name $openaiName `
    --resource-group $ResourceGroupName `
    --query properties.endpoint -o tsv

$openaiKey = az cognitiveservices account keys list `
    --name $openaiName `
    --resource-group $ResourceGroupName `
    --query key1 -o tsv

Write-Host "  ✓ AI Services: $openaiName" -ForegroundColor Green

# Deploy model
Write-Host "  → Deploying gpt-4o-mini model..." -ForegroundColor Gray
$deploymentName = "gpt-4o-mini"
az cognitiveservices account deployment create `
    --name $openaiName `
    --resource-group $ResourceGroupName `
    --deployment-name $deploymentName `
    --model-name "gpt-4o-mini" `
    --model-version "2024-07-18" `
    --model-format "OpenAI" `
    --sku-capacity 10 `
    --sku-name "Standard" `
    --output none 2>$null

Write-Host "  ✓ Model deployed: $deploymentName" -ForegroundColor Green

# Enable diagnostic logging
Write-Host "[5/6] Enabling diagnostic logging..." -ForegroundColor Cyan
$openaiResourceId = az cognitiveservices account show `
    --name $openaiName `
    --resource-group $ResourceGroupName `
    --query id -o tsv

$workspaceResourceId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroupName `
    --workspace-name $workspaceName `
    --query id -o tsv

az monitor diagnostic-settings create `
    --name "ai-security-logs" `
    --resource $openaiResourceId `
    --workspace $workspaceResourceId `
    --logs '[{"category":"Audit","enabled":true},{"category":"RequestResponse","enabled":true}]' `
    --metrics '[{"category":"AllMetrics","enabled":true}]' `
    --output none 2>$null

Write-Host "  ✓ Diagnostic logging enabled" -ForegroundColor Green

# Deploy Function App for proxy
Write-Host "[6/6] Deploying logging proxy..." -ForegroundColor Cyan
$functionAppName = "fn-aiproxy-$Suffix"
$storageName = "staiproxy$Suffix"

# Create storage account
az storage account create `
    --name $storageName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --sku "Standard_LRS" `
    --output none

# Create function app
az functionapp create `
    --name $functionAppName `
    --resource-group $ResourceGroupName `
    --storage-account $storageName `
    --consumption-plan-location $Location `
    --runtime "powershell" `
    --runtime-version "7.4" `
    --functions-version 4 `
    --output none

# Configure function app settings
az functionapp config appsettings set `
    --name $functionAppName `
    --resource-group $ResourceGroupName `
    --settings `
        "OPENAI_ENDPOINT=$openaiEndpoint" `
        "OPENAI_KEY=$openaiKey" `
        "LOG_ANALYTICS_WORKSPACE_ID=$workspaceId" `
        "LOG_ANALYTICS_SHARED_KEY=$workspaceKey" `
    --output none

Write-Host "  ✓ Function app: $functionAppName" -ForegroundColor Green

# Deploy proxy code
Write-Host "  → Deploying proxy code..." -ForegroundColor Gray
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$proxyPath = Join-Path $scriptDir "modules" "proxy"

if (Test-Path $proxyPath) {
    $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "proxy-$Suffix.zip"
    Compress-Archive -Path "$proxyPath/*" -DestinationPath $tempZip -Force
    
    az functionapp deployment source config-zip `
        --resource-group $ResourceGroupName `
        --name $functionAppName `
        --src $tempZip `
        --output none 2>$null
    
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ Proxy code deployed" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Proxy code not found at $proxyPath" -ForegroundColor Yellow
}

# Get function URL
$functionKey = az functionapp keys list `
    --name $functionAppName `
    --resource-group $ResourceGroupName `
    --query functionKeys.default -o tsv 2>$null

$proxyUrl = "https://$functionAppName.azurewebsites.net/api/AIProxy?code=$functionKey"

# Save config
$config = @{
    ResourceGroup = $ResourceGroupName
    Location = $Location
    Suffix = $Suffix
    Endpoint = $openaiEndpoint
    ApiKey = $openaiKey
    DeploymentName = $deploymentName
    OpenAIName = $openaiName
    WorkspaceName = $workspaceName
    WorkspaceId = $workspaceId
    FunctionAppName = $functionAppName
    ProxyUrl = $proxyUrl
}

$configPath = Join-Path $scriptDir "lab_config.json"
$config | ConvertTo-Json -Depth 10 | Out-File $configPath -Encoding UTF8

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                    DEPLOYMENT COMPLETE                         " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resources created:" -ForegroundColor Yellow
Write-Host "  • Resource Group: $ResourceGroupName"
Write-Host "  • AI Services: $openaiName"
Write-Host "  • Model: $deploymentName"
Write-Host "  • Log Analytics: $workspaceName"
Write-Host "  • Proxy Function: $functionAppName"
Write-Host ""
Write-Host "Config saved to: $configPath" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. cd Lab-1-Content-Safety"
Write-Host "  2. ./solution/Test-ContentFilters.ps1"
Write-Host ""
Write-Host "Estimated cost: ~\$5-10 for the full lab" -ForegroundColor Gray
Write-Host "Run ./Cleanup-Lab.ps1 when done to delete resources" -ForegroundColor Gray
Write-Host ""
