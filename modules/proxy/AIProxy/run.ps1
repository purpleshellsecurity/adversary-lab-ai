using namespace System.Net

param($Request, $TriggerMetadata)

# Get environment variables
$openaiEndpoint = $env:OPENAI_ENDPOINT
$openaiKey = $env:OPENAI_KEY
$workspaceId = $env:LOG_ANALYTICS_WORKSPACE_ID
$workspaceKey = $env:LOG_ANALYTICS_SHARED_KEY

# Parse request
$body = $Request.Body

$deployment = $body.deployment ?? "gpt-4o-mini"
$messages = $body.messages
$maxTokens = $body.max_tokens ?? 1000
$attackType = $body.attack_type ?? "none"
$attackName = $body.attack_name ?? "none"

# Extract prompt from messages
$userPrompt = ($messages | Where-Object { $_.role -eq "user" } | Select-Object -Last 1).content
$systemPrompt = ($messages | Where-Object { $_.role -eq "system" } | Select-Object -First 1).content

# Build Azure OpenAI request
$openaiUrl = "$openaiEndpoint/openai/deployments/$deployment/chat/completions?api-version=2024-02-15-preview"

$openaiBody = @{
    messages = $messages
    max_tokens = $maxTokens
} | ConvertTo-Json -Depth 10

$headers = @{
    "api-key" = $openaiKey
    "Content-Type" = "application/json"
}

$startTime = Get-Date
$httpStatus = [HttpStatusCode]::OK
$azureErrorBody = $null

try {
    # Call Azure OpenAI
    $response = Invoke-RestMethod -Uri $openaiUrl -Method Post -Headers $headers -Body $openaiBody -ErrorAction Stop
    $aiResponse = $response.choices[0].message.content
    $tokensUsed = $response.usage.total_tokens
    $status = "success"
    $filterTriggered = $null
} catch {
    $aiResponse = $_.Exception.Message
    $tokensUsed = 0
    $status = "blocked"
    $filterTriggered = $null
    
    # Get the HTTP status code
    if ($_.Exception.Response) {
        $httpStatus = $_.Exception.Response.StatusCode
    } else {
        $httpStatus = [HttpStatusCode]::InternalServerError
    }
    
    # Try to extract the Azure error body with content_filter_result
    try {
        $errorDetails = $_.ErrorDetails.Message
        if ($errorDetails) {
            $azureErrorBody = $errorDetails | ConvertFrom-Json
            
            # Extract which filter triggered
            $filterResult = $azureErrorBody.error.innererror.content_filter_result
            if ($filterResult) {
                $triggered = @()
                if ($filterResult.jailbreak.filtered -or $filterResult.jailbreak.detected) { $triggered += "jailbreak" }
                if ($filterResult.indirect_attack.filtered -or $filterResult.indirect_attack.detected) { $triggered += "indirect_attack" }
                if ($filterResult.hate.filtered) { $triggered += "hate:$($filterResult.hate.severity)" }
                if ($filterResult.self_harm.filtered) { $triggered += "self_harm:$($filterResult.self_harm.severity)" }
                if ($filterResult.sexual.filtered) { $triggered += "sexual:$($filterResult.sexual.severity)" }
                if ($filterResult.violence.filtered) { $triggered += "violence:$($filterResult.violence.severity)" }
                if ($filterResult.profanity.filtered) { $triggered += "profanity" }
                $filterTriggered = $triggered -join ","
            }
        }
    } catch {
        # Could not parse error details
    }
}

$duration = ((Get-Date) - $startTime).TotalMilliseconds

# Log to Log Analytics
$logEntry = @{
    TimeGenerated = (Get-Date).ToUniversalTime().ToString("o")
    Prompt = $userPrompt
    SystemPrompt = $systemPrompt
    Response = $aiResponse
    TokensUsed = $tokensUsed
    CallerIP = $Request.Headers["X-Forwarded-For"] ?? "unknown"
    AttackType = $attackType
    AttackName = $attackName
    Model = $deployment
    Duration = $duration
    Status = $status
    FilterTriggered = $filterTriggered
    HttpStatusCode = [int]$httpStatus
}

# Build Log Analytics signature
$dateString = [DateTime]::UtcNow.ToString("r")
$jsonLog = @($logEntry) | ConvertTo-Json -Depth 10
$bytesToEncode = [System.Text.Encoding]::UTF8.GetBytes($jsonLog)
$contentLength = $bytesToEncode.Length

$stringToHash = "POST`n$contentLength`napplication/json`nx-ms-date:$dateString`n/api/logs"
$bytesToHash = [System.Text.Encoding]::UTF8.GetBytes($stringToHash)
$keyBytes = [Convert]::FromBase64String($workspaceKey)
$hmac = New-Object System.Security.Cryptography.HMACSHA256
$hmac.Key = $keyBytes
$calculatedHash = $hmac.ComputeHash($bytesToHash)
$signature = [Convert]::ToBase64String($calculatedHash)
$authorization = "SharedKey ${workspaceId}:${signature}"

# Send to Log Analytics
$logUrl = "https://$workspaceId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
$logHeaders = @{
    "Authorization" = $authorization
    "Log-Type" = "AISecurityLogs"
    "x-ms-date" = $dateString
    "Content-Type" = "application/json"
}

try {
    Invoke-RestMethod -Uri $logUrl -Method Post -Headers $logHeaders -Body $jsonLog | Out-Null
} catch {
    Write-Warning "Failed to log: $($_.Exception.Message)"
}

# Build response
if ($status -eq "success") {
    # Success - return normal response
    $responseBody = @{
        choices = @(
            @{
                message = @{
                    role = "assistant"
                    content = $aiResponse
                }
            }
        )
        usage = @{
            total_tokens = $tokensUsed
        }
        logged = $true
    }
} else {
    # Error/Blocked - pass through the Azure error body if we have it
    if ($azureErrorBody) {
        $responseBody = $azureErrorBody
        # Add our logging flag
        $responseBody | Add-Member -NotePropertyName "logged" -NotePropertyValue $true -Force
    } else {
        # Fallback error format
        $responseBody = @{
            error = @{
                message = $aiResponse
                code = "error"
                status = [int]$httpStatus
            }
            logged = $true
        }
    }
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $httpStatus
    Body = ($responseBody | ConvertTo-Json -Depth 10)
    ContentType = "application/json"
})
