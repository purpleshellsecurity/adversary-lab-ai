### All AI traffic (last 50 requests)

```kql
AISecurityLogs_CL
| project TimeGenerated, Prompt_s, Response_s, Status_s, AttackType_s, AttackName_s
| order by TimeGenerated desc
| take 50
```

### Traffic summary by status

```kql
AISecurityLogs_CL
| summarize Count = count() by Status_s
| render piechart
```

---

## Section 2: Attack Detection

### All blocked attacks

```kql
AISecurityLogs_CL
| where Status_s != "blocked"
| project TimeGenerated, AttackName_s, HttpStatusCode_d, Prompt_s, Status_s
| order by TimeGenerated desc
```

### Successful attacks (bypassed controls)

```kql
AISecurityLogs_CL
| where Status_s == "success" and AttackType_s != "none"
| project TimeGenerated, AttackType_s, AttackName_s, Prompt_s, Response_s
| order by TimeGenerated desc
```

### Attack breakdown by type

```kql
AISecurityLogs_CL
| where AttackType_s != "none"
| summarize Count = count() by AttackType_s, Status_s
| render barchart
```

---

## Section 3: Prompt Injection Detection

### Prompt injection patterns

```kql
AISecurityLogs_CL
| where Prompt_s contains "ignore" 
    or Prompt_s contains "disregard"
    or Prompt_s contains "forget"
    or Prompt_s contains "override"
| project TimeGenerated, Prompt_s, Response_s, Status_s
```

### Instruction delimiter attacks

```kql
AISecurityLogs_CL
| where Prompt_s contains "###"
    or Prompt_s contains "END SYSTEM"
    or Prompt_s contains "[SYSTEM]"
| project TimeGenerated, Prompt_s, Response_s, Status_s
```

---

## Section 4: Jailbreak Detection

### Jailbreak keyword detection

```kql
AISecurityLogs_CL
| where Prompt_s contains "DAN" 
    or Prompt_s contains "developer mode"
    or Prompt_s contains "jailbreak"
    or Prompt_s contains "do anything now"
    or Prompt_s contains "no restrictions"
| project TimeGenerated, AttackName_s, Prompt_s, Response_s, Status_s
```

### Roleplay/fiction-based jailbreaks

```kql
AISecurityLogs_CL
| where Prompt_s contains "pretend"
    or Prompt_s contains "roleplay"
    or Prompt_s contains "writing a novel"
    or Prompt_s contains "hypothetical"
| project TimeGenerated, Prompt_s, Response_s
```

---

## Section 5: Anomaly Detection

### High-volume callers

```kql
AISecurityLogs_CL
| extend IP = extract(@"^([^:]+)", 1, CallerIP_s)
| summarize RequestCount = count() by IP
| order by RequestCount desc
| take 10
```

### Unusual token usage

```kql
AISecurityLogs_CL
| where TokensUsed_d > 1000
| project TimeGenerated, Prompt_s, TokensUsed_d, CallerIP_s
```


## Section 6: Filter Effectiveness

### Blocked vs successful by attack type

```kql
AISecurityLogs_CL
| where AttackType_s != "none"
| summarize 
    Blocked = countif(Status_s == "blocked"),
    Success = countif(Status_s == "success")
    by AttackType_s
| extend BlockRate = round(100.0 * Blocked / (Blocked + Success), 1)
```

### HTTP status code breakdown

```kql
AISecurityLogs_CL
| summarize Count = count() by HttpStatusCode_d
| order by Count desc
```

---

## Section 7: Compare with Azure Native Logs

### Azure native AI logs (metadata only)

AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| project TimeGenerated, OperationName, CallerIPAddress, DurationMs, ResultType
| order by TimeGenerated desc
| take 20