# Lab 3: Log Analysis

Hunt for attacks in the logs using KQL.

## The Logging Gap

| Data | Azure Native | Our Proxy |
|------|--------------|-----------|
| Timestamp | ✅ | ✅ |
| Caller IP | ✅ | ✅ |
| Token count | ✅ | ✅ |
| Prompt content | ❌ | ✅ |
| Response content | ❌ | ✅ |

> **Key insight:** Azure doesn't log what was asked or answered. That's why we built the proxy.

## Access Logs

1. Go to **Azure Portal**
2. Find your Log Analytics workspace (name is in `lab_config.json`)
3. Click **Logs**

## Queries

See `queries.kql` for the full list. Key ones below.

**All attacks:**

```kql
AISecurityLogs_CL
| project TimeGenerated, AttackName_s, Status_s, Prompt_s
| order by TimeGenerated desc
```

**Blocked vs succeeded:**

```kql
AISecurityLogs_CL
| where AttackType_s != "none"
| summarize 
    Blocked = countif(Status_s == "blocked"), 
    Success = countif(Status_s == "success") 
    by AttackType_s
```

**Data leakage patterns:**

```kql
AISecurityLogs_CL
| where Response_s contains "SSN" or Response_s contains "password"
| project TimeGenerated, Prompt_s, Response_s
```

## What You Should See

- Attacks with `Status_s == "blocked"` and `FilterTriggered_s == "jailbreak"`
- Attacks with `Status_s == "success"` that bypassed filters
- Full prompts and responses for forensic analysis

## The Real Problem

You can't detect AI attacks without logging prompts and responses. Here are your options:

| Solution | Cost | Logs Prompts/Responses? |
|----------|------|-------------------------|
| This lab's proxy | Free tier Function App | ✅ Yes |
| Azure API Management | ~$35-280/month | ✅ Yes (enable "Log LLM messages") |
| Native diagnostic settings | ~$2.76/GB ingestion | ❌ No—metadata only |
<br>

> [!WARNING]  
> Azure's "Request and Response Logs" are misleading—they log metadata (tokens, latency, status codes) but NOT prompt text or response content.

