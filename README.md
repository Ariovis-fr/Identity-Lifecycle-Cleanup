# Identity Lifecycle Cleanup

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Entra ID](https://img.shields.io/badge/Entra_ID-Supported-0078D4?logo=microsoft-azure)
![Active Directory](https://img.shields.io/badge/Active_Directory-Supported-green?logo=windows)
![Netwrix](https://img.shields.io/badge/Netwrix_Identity_Manager-Supported-purple)
![IAM](https://img.shields.io/badge/IAM-Identity_Management-orange)
![SQL Server](https://img.shields.io/badge/SQL_Server-Required-red?logo=microsoft-sql-server)
![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)

## Description

PowerShell automation to identify and manage inactive accounts in **Entra ID**, **Active Directory**, work with **Netwrix  Identity Manager (Usercube)**. Tracks users with no sign-in activity for 75-90 days and syncs data to SQL Server for auditing, reporting, and automated cleanup workflows.

### Key Features
- 🔍 **Automated User Tracking** - Monitors user sign-in activity from Entra ID, Active Directory, and Netwrix Identity Manager (NIM)
- 📊 **SQL Database Integration** - Stores historical data for auditing and compliance
- ⏰ **Configurable Thresholds** - Customizable inactivity periods (default: 75 days for Entra ID, 90 days for AD)
- 📧 **Reminder System** - Tracks multiple reminder notifications (Relance1, Relance2)
- 🔐 **IAM Compliance** - Helps maintain security by managing dormant accounts
- 🔧 **Multi-Platform Support** - Works with both native AD/Entra ID and Netwrix Identity Manager environments

## Database Structure

The solution uses two main tables to store user activity data:

```mermaiderDiagram
    ADUserLogon {
        INT Id PK "Primary Key (Identity)"
        VARCHAR(100) SamAccountName "User account name"
        VARCHAR(200) Name "Full name"
        VARCHAR(500) Status "Account status"
        DATETIME LastLogon "Last logon timestamp"
        INT Days "Days since last logon"
        VARCHAR(100) Mail "User email"
        VARCHAR(100) MailManager "Manager email"
        BIT Relance1 "First reminder sent"
        BIT Relance2 "Second reminder sent"
    }
    
    EntraIDUserSignIn {
        INT Id PK "Primary Key (Identity)"
        NVARCHAR(255) DisplayName "User display name"
        NVARCHAR(255) UserPrincipalName "UPN"
        DATETIME LastSignIn "Last sign-in timestamp"
    }
```

**ADUserLogon**: Stores information from Domain Controllers (Active Directory)  
**EntraIDUserSignIn**: Stores information from Microsoft Entra ID (Azure AD)


## EntraToSQL Process Flow

The `EntraToSQL.ps1` script follows this workflow:

```mermaid
flowchart TD
    A[Start Script] --> B[Connect to Microsoft Graph API]
    B --> C[Set Inactivity Threshold<br/>Default: 75 days]
    C --> D[Calculate Cutoff Date<br/>Today - 75 days]
    D --> E[Query All Entra ID Users]
    E --> F{Filter Users<br/>Last Sign-In < Cutoff Date?}
    F -->|Yes| G[Add to Inactive Users List]
    F -->|No| H[Skip User]
    G --> I[Display Results to Console]
    H --> I
    I --> J[Connect to SQL Server]
    J --> K[Prepare INSERT Statement]
    K --> L{For Each Inactive User}
    L --> M[Insert User Data<br/>DisplayName, UPN, LastSignIn]
    M --> N{More Users?}
    N -->|Yes| L
    N -->|No| O[Close SQL Connection]
    O --> P[Display Success Message]
    P --> Q[End Script]
    
    style A fill:#90EE90
    style Q fill:#FFB6C1
    style F fill:#FFD700
    style J fill:#87CEEB
```

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.

You are free to use, modify, and distribute this software under the terms of the GPL-3.0 license. See the [LICENSE](LICENSE) file for full details.

### Key Points:
- ✅ Free to use and modify
- ✅ Must disclose source code
- ✅ Must include original license and copyright notice
- ✅ Changes must be documented
- ❌ No warranty provided

## Requirements

- PowerShell 5.1 or higher
- Microsoft Graph PowerShell SDK
- SQL Server (with appropriate credentials)
- Active Directory PowerShell Module (for AD integration)
- Netwrix Identity Manager (NIM) - Optional, for NIM-based environments
- Appropriate permissions:
  - Entra ID: `User.Read.All`, `AuditLog.Read.All`
  - Active Directory: Read access to user objects
  - Netwrix NIM: API access or PowerShell module integration
  - SQL Server: Write access to target database

---

**Maintained by**: Ariovis-fr  

**Repository**: [EntraID Inactive User Cleanup Automation](https://github.com/Ariovis-fr/Entra-ID-Inactive-User-Cleanup-Automation)
