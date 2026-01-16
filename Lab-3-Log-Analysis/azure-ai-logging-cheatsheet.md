# Azure AI Logging Cheatsheet

Quick reference for what Azure AI services log vs. what you need for security.

## The Critical Gap

| Data Point | Azure Native | Custom Proxy |
|------------|--------------|--------------|
| Timestamp | ✅ | ✅ |
| Caller IP | ✅ | ✅ |
| Operation name | ✅ | ✅ |
| Token count | ✅ | ✅ |
| Duration | ✅ | ✅ |
| HTTP status | ✅ | ✅ |
| **Prompt content** | ❌ | ✅ |
| **Response content** | ❌ | ✅ |
| **Attack indicators** | ❌ | ✅ |

**Key insight:** Azure logs metadata, not content. You cannot detect prompt injection, jailbreaks, or data leakage from Azure native logs alone.

---

## Azure Native Log Categories

### AzureDiagnostics

Enable via Diagnostic Settings on your AI resource.

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| project TimeGenerated, OperationName, CallerIPAddress, DurationMs
```

**Contains:**
- Request metadata
- Performance metrics
- Error codes
- Caller information

**Does NOT contain:**
- Actual prompts
- Actual responses
- Message content

### AzureMetrics

```kql
AzureMetrics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| project TimeGenerated, MetricName, Total
```

**Useful metrics:**
- TokenTransaction (token usage)
- SuccessfulCalls
- TotalErrors
- Latency

---

## Why This Gap Exists

This is a **deliberate design choice**, not an oversight:

1. **Privacy** - Prompts may contain PII
2. **Cost** - Logging all content is expensive
3. **Compliance** - Some industries prohibit logging
4. **Scale** - High-volume services generate huge logs

Microsoft leaves content logging to the customer to implement based on their requirements.

---

## Bridging the Gap

### Option 1: Logging Proxy (This Lab)

Route all traffic through an Azure Function that:
- Captures full request/response
- Sends to Log Analytics
- Adds security metadata

**Pros:** Full visibility, custom fields
**Cons:** Additional infrastructure, latency

### Option 2: Application Insights

If using Azure OpenAI SDK, instrument with App Insights:

```python
from azure.monitor.opentelemetry import configure_azure_monitor
configure_azure_monitor()
```

**Pros:** Integrated with Azure
**Cons:** Requires code changes, limited customization

### Option 3: API Management

Put Azure API Management in front of AI services:
- Request/response logging
- Rate limiting
- Analytics

**Pros:** Enterprise features
**Cons:** Cost, complexity

---

## What to Log for Security

Minimum viable security logging:

| Field | Why |
|-------|-----|
| Timestamp | Timeline analysis |
| Caller IP | Attribution |
| User identity | Accountability |
| Full prompt | Attack detection |
| Full response | Data leakage detection |
| Token count | Anomaly detection |
| Model/deployment | Scope |
| Session ID | Conversation tracking |

Enhanced security logging:

| Field | Why |
|-------|-----|
| Attack classification | Automated detection |
| Filter triggers | Understanding blocks |
| Latency | Performance anomalies |
| Conversation history | Context |

---

## Detection Opportunities

What you can detect with proper logging:

| Attack | Detection Method |
|--------|------------------|
| Prompt injection | Keyword patterns in prompt |
| Jailbreak | Known jailbreak strings |
| Data exfiltration | PII patterns in response |
| System prompt theft | Instruction patterns in response |
| Abuse | High volume, unusual patterns |
| Model extraction | Repeated similar prompts |

What you CANNOT detect without content logging:

- Whether an attack succeeded
- What data was leaked
- The specific attack technique
- User intent

---

## Log Retention Recommendations

| Log Type | Retention | Reason |
|----------|-----------|--------|
| Security events | 1 year | Incident investigation |
| All traffic | 90 days | Trend analysis |
| Metrics | 30 days | Performance monitoring |

Consider:
- Compliance requirements (GDPR, HIPAA)
- Storage costs
- Query performance

---

## Quick Setup Checklist

- [ ] Enable AzureDiagnostics on AI resource
- [ ] Enable AzureMetrics on AI resource
- [ ] Deploy logging proxy or APIM
- [ ] Create Log Analytics workspace
- [ ] Set up retention policies
- [ ] Build detection queries
- [ ] Create alerts for critical events

---

## Resources

- [Azure OpenAI Logging](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/monitoring)
- [Log Analytics KQL](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/get-started-queries)
- [OWASP LLM Top 10](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
