# AdcsPkiSolution

This Visual Studio solution provides an integration for Active Directory Certificate Services (ADCS) with Public Key Infrastructure (PKI) functionality. It consists of two projects:
- **AdcsExitModule**: A .NET Framework 4.7.2 Exit Module for handling ADCS certificate events (e.g., issuance, revocation).
- **AdcsCertificateWebApi**: A .NET 8 REST API for managing certificate data, integrated with a SQL Server database.

**Note**: This is a proprietary project for internal use by Justitiële ICT Organisatie. All rights are reserved. Unauthorized use, copying, or distribution is prohibited.

## Solution Structure
The solution is organized as follows:
```
AdcsPkiSolution
├── AdcsExitModule
│   ├── AdcsExitModule.csproj
│   ├── Exit.cs
│   ├── ExitAppConfig.cs
│   ├── ExitManage.cs
│   ├── Files
│   │   └── Install-CertSrvExitModule.ps1
│   └── Properties
├── AdcsCertificateWebApi
│   ├── AdcsCertificateWebApi.csproj
│   ├── Program.cs
│   ├── appsettings.json
│   ├── Controllers
│   │   ├── CertificateDataController.cs
│   │   ├── CertificatesController.cs
│   │   └── TestController.cs
│   ├── Data
│   │   └── AuthDbContext.cs
│   ├── Middleware
│   │   └── MtlsAuthMiddleware.cs
│   ├── Models
│   │   └── CertificateDataDto.cs
│   ├── Database
│   │   └── SQL-PKI-DB.sql
│   ├── Scripts
│   │   └── Test-api-AdcsCertificateWebApiV2.ps1
└── AdcsPkiSolution.sln
```

## Prerequisites
- **Development Environment**:
  - Visual Studio 2022 (or later) with .NET Framework 4.7.2 and .NET 8 SDK installed.
  - Both projects are configured to target x64 platforms exclusively.
- **Deployment Environment**:
  - Windows Server (x64) with ADCS for `AdcsExitModule`.
  - SQL Server for the database (`AdcsCertificateDbV3`).
  - .NET 8 Hosting Bundle (x64) for `AdcsCertificateWebApi` (e.g., for IIS hosting).
- **Dependencies**:
  - `AdcsExitModule`: NuGet packages like `SysadminsLV.PKI` and `Newtonsoft.Json`.
  - `AdcsCertificateWebApi`: NuGet packages like `Microsoft.EntityFrameworkCore.SqlServer` and `Serilog`.
- **PowerShell**: PowerShell 5.1 or later for running `Install-CertSrvExitModule.ps1` and `Test-api-AdcsCertificateWebApiV2.ps1`.

## Setup Instructions

### 1. Clone the Repository
Clone the private repository to your local machine:
```bash
git clone https://github.com/your-username/AdcsPkiSolution.git
cd AdcsPkiSolution
```

### 2. Configure the Database
1. Run the `SQL-PKI-DB.sql` script located in `AdcsCertificateWebApi\Database\` to create the database (`AdcsCertificateDbV3`) on a SQL Server instance.
2. Ensure the gMSA account (`FRS98470\gmsa_pki20api$`) has appropriate permissions on the database.
3. Configure the database connection string in `AdcsCertificateWebApi\appsettings.json`:
   ```json
   {
     "ConnectionStrings": {
       "AdcsDb": "Server=s98470a24b3a001.FRS98470.localdns.nl;Database=AdcsCertificateDbV3;Trusted_Connection=True;"
     }
   }
   ```
   Ensure the `appsettings.json` file is excluded from version control (added to `.gitignore`) if it contains sensitive data.

### 3. Build the Solution
1. Open `AdcsPkiSolution.sln` in Visual Studio.
2. Ensure the solution platform is set to `x64` in **Build > Configuration Manager**.
3. Build the solution (`Ctrl+Shift+B`) to restore NuGet packages and compile both projects.

### 4. Deploy and Register AdcsExitModule
1. Build `AdcsExitModule` to generate `AdcsExitModule.dll` in `AdcsExitModule\bin\x64\Debug\` or `Release`.
2. Use the PowerShell script `AdcsExitModule\Files\Install-CertSrvExitModule.ps1` to register the Exit Module in ADCS on a Windows Server (x64). Run the script with elevated privileges (Run as Administrator):
   ```powershell
   .\AdcsExitModule\Files\Install-CertSrvExitModule.ps1 -Path .\AdcsExitModule\bin\x64\Release\AdcsExitModule.dll -ApiUrl "https://adcscertificateapi.tenant47.minjenv.nl/api/certificate/issue" -BufferDir "C:\PKIExitBuffer" -LogBaseDir "C:\Logs" -LogLevel 3 -ApiKey "X7K9P2M4Q8J5R3L1N6V0T2Y4W8Z9A3B5C" -AddToCA -Restart
   ```
   **Parameters**:
   - `-Path`: Path to `AdcsExitModule.dll` (required).
   - `-ApiUrl`: URL of the certificate issuance endpoint (default: `https://adcscertificateapi.tenant47.minjenv.nl/api/certificate/issue`).
   - `-BufferDir`: Directory for buffering certificate data (default: `C:\PKIExitBuffer`).
   - `-LogBaseDir`: Directory for log files (default: `C:\Logs`).
   - `-LogLevel`: Logging level (default: `3` for Debug).
   - `-ApiKey`: API key for the Web API (default: provided in script).
   - `-RegisterOnly`: Only register the COM component without adding to CA.
   - `-AddToCA`: Add the module to the Certification Authority.
   - `-Restart`: Restart the CertSvc service after registration.
3. Verify logs are written to `C:\Logs\AdcsExitModule.log`.

### 5. Deploy AdcsCertificateWebApi
1. Build `AdcsCertificateWebApi` to generate the output in `AdcsCertificateWebApi\bin\x64\Debug\net8.0\` or `Release`.
2. Deploy to a web server (e.g., IIS) with the .NET 8 Hosting Bundle (x64) installed.
3. Configure the IIS Application Pool to disable 32-bit applications:
   - In IIS Manager, go to **Application Pools > [Your Pool] > Advanced Settings**.
   - Set **Enable 32-Bit Applications** to `False`.
4. Ensure the `appsettings.json` file is copied to the deployment directory and configured correctly.
5. Update the API configuration in `Program.cs` (e.g., Serilog logging to `C:\Logs\AdcsCertificateWebApi.log`).
6. Test the API using the PowerShell script `AdcsCertificateWebApi\Scripts\Test-api-AdcsCertificateWebApiV2.ps1`:
   ```powershell
   .\Test-api-AdcsCertificateWebApiV2.ps1
   ```
   This tests endpoints like `/api/Certificates/expiring` and logs results to `C:\Logs\AdcsCertificateWebApiTest.log`.

### 6. Test the Solution
- **AdcsExitModule**: Simulate a certificate event (e.g., issuance) in ADCS and verify the module processes it correctly (check logs at `C:\Logs\AdcsExitModule.log`).
- **AdcsCertificateWebApi**: Start the API in Visual Studio (F5) or on the deployed server and test endpoints using the provided PowerShell script or tools like Postman.

## Security Notes
- **Sensitive Data**: The `appsettings.json` file contains sensitive information (e.g., database connection strings). Ensure it is excluded from version control by adding it to `.gitignore`:
  ```plaintext
  appsettings.json
  appsettings.*.json
  ```
  Use environment-specific configuration files (e.g., `appsettings.Production.json`) for deployment.
- **Private Repository**: This repository is private to restrict access to authorized team members only.
- **Logging**: Ensure log directories (`C:\Logs`) and buffer directories (`C:\PKIExitBuffer`) have appropriate permissions to prevent unauthorized access.
- **API Key**: The API key in `Install-CertSrvExitModule.ps1` is encrypted and stored in the registry. Ensure it is securely managed and not hardcoded in production environments.

## Contributing
This is an internal project. Contact [Your Contact Info] for access or contribution guidelines.

## Copyright
Copyright © 2025 Justitiële ICT Organisatie. All Rights Reserved.