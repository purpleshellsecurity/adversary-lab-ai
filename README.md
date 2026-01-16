# AI Adversary Lab

Run attacks against Azure AI to see what gets blocked vs. what slips through.
<br>
## Prerequisites

**PowerShell 7+**
```bash
# macOS
brew install powershell/tap/powershell

# Windows
winget install Microsoft.PowerShell

# Linux
# See: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux
```

**Azure CLI**
```bash
# macOS
brew install azure-cli

# Windows
winget install Microsoft.AzureCLI

# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**Az PowerShell Module**
```powershell
Install-Module Az -Scope CurrentUser -Force
```

---

## Quick Start

### 1. Deploy

```powershell
./Deploy-Lab.ps1
```

### 2. Configure Content Filters

1. Go to [AI Foundry](https://ai.azure.com) → your project
2. **Safety + security** → **Content filters** → **Create**
3. Enable:
   - Prompt shields for jailbreak attacks → **Annotate and block**
   - Prompt shields for indirect attacks → **Annotate and block**
4. **Apply to your deployment** ← Critical!

### 3. Run the Labs

```powershell
# Lab 1: See what filters exist
cd Lab-1-Content-Safety
./Test-ContentFilters.ps1

# Lab 2: Run attacks
cd ../Lab-2-Basic-Attacks
./Invoke-PromptInjection.ps1
./Invoke-Jailbreak.ps1

# Lab 3: Find attacks in logs
# Open Azure Portal → Log Analytics → Run queries from queries.md
```

### 4. Clean Up

```powershell
./Cleanup-Lab.ps1
```

---

## Structure

```
├── Deploy-Lab.ps1
├── Cleanup-Lab.ps1
├── Lab-1-Content-Safety/
│   └── Test-ContentFilters.ps1
├── Lab-2-Basic-Attacks/
│   ├── Invoke-PromptInjection.ps1
│   └── Invoke-Jailbreak.ps1
├── Lab-3-Log-Analysis/
│   └── queries.md
└── modules/proxy/
```

---

## Framework Mapping

| Attack | OWASP LLM 2025 | MITRE ATLAS |
|--------|----------------|-------------|
| Prompt Injection | LLM01 | AML.T0051 |
| Jailbreak | LLM01 | AML.T0054 |

---
