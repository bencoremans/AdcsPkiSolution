# API Endpoints voor AuthorizedServers (ManageController)

De `ManageController` in de `AdcsCertificateWebApi` biedt RESTful endpoints voor het beheren van `AuthorizedServer`-entiteiten in de `AdcsCertificateDbV2`-database. Deze entiteiten vertegenwoordigen servers die gemachtigd zijn om certificaten te beheren, met eigenschappen zoals `ServerID`, `AdcsServerAccount`, `AdcsServerName`, `ServerGUID`, `Description`, `IsActive`, en `CreatedAt`. Alle endpoints vereisen Kerberos-authenticatie (`Negotiate`) en retourneren JSON-responsen, tenzij anders vermeld.

## Algemene Opmerkingen
- **Authenticatie**: Alle endpoints vereisen Kerberos-authenticatie. Een initiële `401 Unauthorized` wordt verwacht, gevolgd door een succesvolle aanroep met geldige credentials.
- **Foutafhandeling**: Fouten worden geretourneerd in JSON-formaat (`application/problem+json`) voor clientfouten zoals `400 Bad Request`. Veelvoorkomende fouten zijn:
  - `401 Unauthorized`: Geen geldige Kerberos-ticket.
  - `403 Forbidden`: Gebruiker heeft onvoldoende rechten (bijv. niet in de groep `FRS98470\grp98470c47-sys-l-A47-ManangeAPI`).
  - `404 Not Found`: Ongeldige `ServerID`.
  - `409 Conflict`: Dubbele `AdcsServerAccount` of `AdcsServerName`.
- **Logging**: API-gebeurtenissen worden gelogd naar `C:\Logs\AdcsCertificateApi.log`. Testresultaten worden gelogd naar `C:\Logs\AdcsTestResults.log` via het script `Test-ManageControllerEndpoints.ps1`.
- **Database**: De endpoints communiceren met de `AdcsCertificateDbV2`-database op server `s98470a24b3a001.frs98470.localdns.nl`.

## Endpoints

### 1. GET /api/Manage/AuthorizedServers
**Beschrijving**: Haalt een lijst op van alle gemachtigde servers.

**Methode**: GET

**Request**:
- **Pad**: `/api/Manage/AuthorizedServers`
- **Headers**:
  - `Content-Type: application/json` (optioneel)
  - `Authorization: Negotiate <token>` (Kerberos-authenticatie)
- **Body**: Geen

**Response**:
- **Succes (200 OK)**:
  - **Body**: Een JSON-array van `AuthorizedServer`-objecten.
    ```json
    [
      {
        "ServerID": 1,
        "AdcsServerAccount": "svc-adcs-prod-001",
        "AdcsServerName": "adcs-prod-001",
        "ServerGUID": "123e4567-e89b-12d3-a456-426614174000",
        "Description": "Productie server 001",
        "IsActive": true,
        "CreatedAt": "2025-01-01T12:00:00Z"
      },
      ...
    ]
    ```
- **Fouten**:
  - `401 Unauthorized`: Geen geldige Kerberos-authenticatie.
  - `403 Forbidden`: Gebruiker heeft onvoldoende rechten.

**Voorbeeld**:
```bash
curl -H "Authorization: Negotiate <token>" https://adcscertificateapi.tenant47.minjenv.nl/api/Manage/AuthorizedServers
```

**Opmerkingen**:
- Gebruikt in het testscript om te controleren of alle servers correct worden geretourneerd (bijv. 24 servers in de log van 2025-10-09 20:00:52).

---

### 2. GET /api/Manage/AuthorizedServers/{id}
**Beschrijving**: Haalt de details op van een specifieke server op basis van de `ServerID`.

**Methode**: GET

**Request**:
- **Pad**: `/api/Manage/AuthorizedServers/{id}` (bijv. `/api/Manage/AuthorizedServers/9`)
- **Parameters**:
  - `id` (long): De unieke `ServerID` van de server.
- **Headers**:
  - `Content-Type: application/json` (optioneel)
  - `Authorization: Negotiate <token>`
- **Body**: Geen

**Response**:
- **Succes (200 OK)**:
  - **Body**: Een JSON-object met de serverdetails.
    ```json
    {
      "ServerID": 9,
      "AdcsServerAccount": "svc-adcs-test-001",
      "AdcsServerName": "adcs-test-001",
      "ServerGUID": "987fcdeb-1234-5678-9012-345678901234",
      "Description": "Test server 001",
      "IsActive": true,
      "CreatedAt": "2025-01-01T12:00:00Z"
    }
    ```
- **Fouten**:
  - `401 Unauthorized`: Geen geldige Kerberos-authenticatie.
  - `403 Forbidden`: Gebruiker heeft onvoldoende rechten.
  - `404 Not Found`: Geen server gevonden met de opgegeven `ServerID`.

**Voorbeeld**:
```bash
curl -H "Authorization: Negotiate <token>" https://adcscertificateapi.tenant47.minjenv.nl/api/Manage/AuthorizedServers/9
```

**Opmerkingen**:
- Getest in het script met `ServerID: 9`, wat succesvol was in alle logs.

---

### 3. POST /api/Manage/AuthorizedServers
**Beschrijving**: Maakt een nieuwe `AuthorizedServer`-entiteit aan in de database.

**Methode**: POST

**Request**:
- **Pad**: `/api/Manage/AuthorizedServers`
- **Headers**:
  - `Content-Type: application/json`
  - `Authorization: Negotiate <token>`
- **Body**: Een JSON-object met de eigenschappen van de nieuwe server.
  ```json
  {
    "AdcsServerAccount": "svc-adcs-test-20251009200052",
    "AdcsServerName": "adcs-test-20251009200052",
    "ServerGUID": "05e159ab-43b1-4ef2-8ecc-155637868e71",
    "Description": "Test Server 20251009200052",
    "IsActive": true
  }
  ```

**Response**:
- **Succes (201 Created)**:
  - **Body**: Een JSON-object met de details van de aangemaakte server, inclusief de gegenereerde `ServerID`.
    ```json
    {
      "ServerID": 33,
      "AdcsServerAccount": "svc-adcs-test-20251009200052",
      "AdcsServerName": "adcs-test-20251009200052",
      "ServerGUID": "05e159ab-43b1-4ef2-8ecc-155637868e71",
      "Description": "Test Server 20251009200052",
      "IsActive": true,
      "CreatedAt": "2025-10-09T20:00:52Z"
    }
    ```
  - **Headers**: Bevat een `Location`-header (bijv. `/api/Manage/AuthorizedServers/33`).
- **Fouten**:
  - `400 Bad Request`: Ongeldige invoer (bijv. ontbrekende velden).
  - `401 Unauthorized`: Geen geldige Kerberos-authenticatie.
  - `403 Forbidden`: Gebruiker heeft onvoldoende rechten.
  - `409 Conflict`: `AdcsServerAccount` of `AdcsServerName` bestaat al.

**Voorbeeld**:
```bash
curl -X POST -H "Content-Type: application/json" -H "Authorization: Negotiate <token>" -d '{"AdcsServerAccount":"svc-adcs-test-20251009200052","AdcsServerName":"adcs-test-20251009200052","ServerGUID":"05e159ab-43b1-4ef2-8ecc-155637868e71","Description":"Test Server","IsActive":true}' https://adcscertificateapi.tenant47.minjenv.nl/api/Manage/AuthorizedServers
```

**Opmerkingen**:
- Getest in het script om een nieuwe server aan te maken (ServerID: 33 in de log van 2025-10-09 20:00:52).
- De `POST conflict`-test verifieert dat een poging om een server met een bestaande `AdcsServerAccount` aan te maken een `409 Conflict` retourneert.

---

### 4. PUT /api/Manage/AuthorizedServers/{id}
**Beschrijving**: Werkt een bestaande `AuthorizedServer`-entiteit bij op basis van de `ServerID`.

**Methode**: PUT

**Request**:
- **Pad**: `/api/Manage/AuthorizedServers/{id}` (bijv. `/api/Manage/AuthorizedServers/33`)
- **Parameters**:
  - `id` (long): De unieke `ServerID` van de server.
- **Headers**:
  - `Content-Type: application/json`
  - `Authorization: Negotiate <token>`
- **Body**: Een JSON-object met de bijgewerkte eigenschappen van de server.
  ```json
  {
    "AdcsServerAccount": "svc-adcs-test-20251009200052",
    "AdcsServerName": "adcs-test-20251009200052",
    "ServerGUID": "987fcdeb-1234-5678-9012-345678901234",
    "Description": "Updated Test Server 20251009200052",
    "IsActive": true
  }
  ```

**Response**:
- **Succes (204 No Content)**:
  - **Body**: Geen (leeg).
- **Fouten**:
  - `400 Bad Request`: Ongeldige invoer (bijv. ongeldige `ServerGUID`).
  - `401 Unauthorized`: Geen geldige Kerberos-authenticatie.
  - `403 Forbidden`: Gebruiker heeft onvoldoende rechten.
  - `404 Not Found`: Geen server gevonden met de opgegeven `ServerID`.
  - `409 Conflict`: `AdcsServerAccount` of `AdcsServerName` bestaat al voor een andere server.

**Voorbeeld**:
```bash
curl -X PUT -H "Content-Type: application/json" -H "Authorization: Negotiate <token>" -d '{"AdcsServerAccount":"svc-adcs-test-20251009200052","AdcsServerName":"adcs-test-20251009200052","ServerGUID":"987fcdeb-1234-5678-9012-345678901234","Description":"Updated Test Server","IsActive":true}' https://adcscertificateapi.tenant47.minjenv.nl/api/Manage/AuthorizedServers/33
```

**Opmerkingen**:
- Getest in het script om ServerID: 33 bij te werken (succesvol in de log van 2025-10-09 20:00:52).
- Vereist een volledige `AuthorizedServerDto`.

---

### 5. PUT /api/Manage/AuthorizedServers/{id}/active
**Beschrijving**: Werkt alleen de `IsActive`-status van een bestaande `AuthorizedServer` bij op basis van de `ServerID`.

**Methode**: PUT

**Request**:
- **Pad**: `/api/Manage/AuthorizedServers/{id}/active` (bijv. `/api/Manage/AuthorizedServers/33/active`)
- **Parameters**:
  - `id` (long): De unieke `ServerID` van de server.
- **Headers**:
  - `Content-Type: application/json`
  - `Authorization: Negotiate <token>`
- **Body**: Een directe boolean waarde (`true` of `false`).
  ```json
  true
  ```

**Response**:
- **Succes (204 No Content)**:
  - **Body**: Geen (leeg).
- **Fouten**:
  - `400 Bad Request`: Ongeldige invoer (bijv. geen geldige boolean waarde).
  - `401 Unauthorized`: Geen geldige Kerberos-authenticatie.
  - `403 Forbidden`: Gebruiker heeft onvoldoende rechten.
  - `404 Not Found`: Geen server gevonden met de opgegeven `ServerID`.

**Voorbeeld**:
```bash
curl -X PUT -H "Content-Type: application/json" -H "Authorization: Negotiate <token>" -d 'true' https://adcscertificateapi.tenant47.minjenv.nl/api/Manage/AuthorizedServers/33/active
```

**Opmerkingen**:
- Getest in het script om de `IsActive`-status van ServerID: 33 te wijzigen naar `true` en `false` (succesvol in de log van 2025-10-09 20:00:52).
- Vereenvoudigt het bijwerken van de `IsActive`-status door geen `GET`-aanroep te vereisen.

---

### 6. DELETE /api/Manage/AuthorizedServers/{id}
**Beschrijving**: Verwijdert (soft delete) een bestaande `AuthorizedServer` op basis van de `ServerID`.

**Methode**: DELETE

**Request**:
- **Pad**: `/api/Manage/AuthorizedServers/{id}` (bijv. `/api/Manage/AuthorizedServers/33`)
- **Parameters**:
  - `id` (long): De unieke `ServerID` van de server.
- **Headers**:
  - `Content-Type: application/json` (optioneel)
  - `Authorization: Negotiate <token>`
- **Body**: Geen

**Response**:
- **Succes (204 No Content)**:
  - **Body**: Geen (leeg).
- **Fouten**:
  - `401 Unauthorized`: Geen geldige Kerberos-authenticatie.
  - `403 Forbidden`: Gebruiker heeft onvoldoende rechten.
  - `404 Not Found`: Geen server gevonden met de opgegeven `ServerID`.

**Voorbeeld**:
```bash
curl -X DELETE -H "Authorization: Negotiate <token>" https://adcscertificateapi.tenant47.minjenv.nl/api/Manage/AuthorizedServers/33
```

**Opmerkingen**:
- Getest in het script om ServerID: 33 te verwijderen (succesvol in de log van 2025-10-09 20:00:52).
- Gebruikt soft delete, waarbij de server logisch wordt gemarkeerd als verwijderd.

---

## Aanvullende Informatie
- **Testscript**: Het PowerShell-script `Test-ManageControllerEndpoints.ps1` wordt gebruikt om deze endpoints te testen. Resultaten worden gelogd naar `C:\Logs\AdcsTestResults.log`.
- **Database**: De endpoints communiceren met de `AdcsCertificateDbV2`-database op server `s98470a24b3a001.frs98470.localdns.nl`. Zorg ervoor dat de databaseverbinding correct is geconfigureerd in `appsettings.json`.
- **Logging**: API-gebeurtenissen worden gelogd naar `C:\Logs\AdcsCertificateApi.log`. De waarschuwing `EnableSensitiveDataLogging` kan worden uitgeschakeld in `Program.cs` voor productie:
  ```csharp
  builder.Services.AddDbContext<AuthDbContext>(options =>
      options.UseSqlServer(
          builder.Configuration.GetConnectionString("AuthDb"),
          sqlOptions => sqlOptions.EnableRetryOnFailure(
              maxRetryCount: 5,
              maxRetryDelay: TimeSpan.FromSeconds(10),
              errorNumbersToAdd: null
          )
      )
      .EnableSensitiveDataLogging(builder.Environment.IsDevelopment())
      .EnableDetailedErrors(builder.Environment.IsDevelopment())
  );
  ```