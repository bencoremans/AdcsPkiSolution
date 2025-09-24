using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using System.Diagnostics;
using System.Linq;
using System.DirectoryServices; // For ADSI query
using ADCS.CertMod.Managed;
using ADCS.CertMod.Managed.Exit;
using Microsoft.Win32;
using SysadminsLV.PKI.Cryptography.X509Certificates;

namespace ADCS.CertMod
{
    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [ProgId("AdcsExitModule.Exit")]
    [Guid("34eba06c-24e0-4068-a049-262e871a6d7b")]
    public class Exit : CertExitBase
    {
        private readonly string? _apiUrl;
        private readonly string? _apiKey;
        private readonly string? _bufferDir;
        private readonly ExitAppConfig _appConfig;
        private readonly string _logFilePath;
        private string? _caName; // Store CA name from Initialize
        private static readonly Dictionary<string, string> TemplateNameCache = new(); // Cache for template names
        private const string PROG_ID = "AdcsExitModule.Exit";

        public Exit() : base(CreateInitialLogWriter())
        {
            Logger.LogInformation("Exit module is being initialized.");

            _appConfig = new ExitAppConfig(PROG_ID, Logger);
            _logFilePath = Path.Combine(_appConfig.GetLogBaseDir(), "AdcsCertMod.Exit.log");
            Logger.LogInformation("Log file path set to: {0}", _logFilePath);

            string logDirectory = Path.GetDirectoryName(_logFilePath);
            if (!string.IsNullOrEmpty(logDirectory) && !Directory.Exists(logDirectory))
            {
                try
                {
                    Directory.CreateDirectory(logDirectory);
                    Logger.LogInformation("Log directory created successfully: {0}", logDirectory);
                }
                catch (Exception ex)
                {
                    Logger.LogError("Failed to create log directory {0}: {1}", logDirectory, ex.Message);
                }
            }

            _apiUrl = _appConfig.GetApiUrl();
            _apiKey = _appConfig.GetApiKey();
            _bufferDir = _appConfig.GetBufferDir();

            if (!string.IsNullOrEmpty(_bufferDir) && !Directory.Exists(_bufferDir))
            {
                try
                {
                    Directory.CreateDirectory(_bufferDir);
                    Logger.LogInformation("Buffer directory created successfully: {0}", _bufferDir);
                }
                catch (Exception ex)
                {
                    Logger.LogError("Failed to create buffer directory {0}: {1}", _bufferDir, ex.Message);
                }
            }

            if (!EventLog.SourceExists("PKIExitModule"))
            {
                EventLog.CreateEventSource("PKIExitModule", "Application");
                Logger.LogInformation("Event source PKIExitModule registered.");
            }
        }

        private static LogWriter CreateInitialLogWriter()
        {
            string defaultRegistryPath = @"SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\DefaultCA\ExitModules\AdcsCertMod.Exit";
            using (var key = Registry.LocalMachine.OpenSubKey(defaultRegistryPath))
            {
                string logBaseDir = key?.GetValue("LogBaseDir")?.ToString() ?? @"C:\Logs";
                return new LogWriter("Exit", LogLevel.Information, logBaseDir);
            }
        }

        public override ExitEvents Initialize(string configString)
        {
            Logger.LogInformation("Exit Initialize started. ConfigString: {0}", configString ?? "null");

            _caName = configString ?? "DefaultCA"; // Store CA name
            string registryPath = $@"SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\{_caName}\ExitModules\{PROG_ID}";
            Logger.LogInformation("Intended registry path for CA {0}: {1}", _caName, registryPath);

            using (var key = Registry.LocalMachine.OpenSubKey(registryPath))
            {
                if (key != null)
                {
                    string logBaseDir = key.GetValue("LogBaseDir")?.ToString() ?? @"C:\Logs";
                    Logger.LogInformation("Verified log base directory from registry: {0}", logBaseDir);

                    object logLevelValue = key.GetValue("LogLevel");
                    if (logLevelValue != null && logLevelValue is int level)
                    {
                        LogLevel newLevel = (LogLevel)level;
                        Logger.LogInformation("Retrieved log level from registry: {0} (value: {1})", newLevel, level);
                        Logger.LogLevel = newLevel;
                    }
                    else
                    {
                        Logger.LogInformation("No valid LogLevel found in registry, using default: Information (3)");
                    }
                }
                else
                {
                    Logger.LogWarning("Registry key {0} not found, using default log path: {1}", registryPath, _logFilePath);
                }
            }

            if (_appConfig.InitializeConfig())
            {
                Logger.LogInformation("Configuration successfully initialized.");
                return ExitEvents.AllEvents;
            }
            Logger.LogWarning("Configuration initialization failed.");
            return ExitEvents.None;
        }

        private string? GetTemplateNameFromAD(string? templateOID)
        {
            if (string.IsNullOrEmpty(templateOID))
            {
                Logger.LogWarning("Template OID is empty, cannot query AD for template name.");
                return null;
            }

            // Check cache first
            if (TemplateNameCache.TryGetValue(templateOID, out var cachedName))
            {
                Logger.LogDebug("Template name retrieved from cache for OID {0}: {1}", templateOID, cachedName);
                return cachedName;
            }

            try
            {
                // Get Configuration partition dynamically
                string configPath;
                try
                {
                    using (var rootDse = new DirectoryEntry("LDAP://RootDSE"))
                    {
                        configPath = rootDse.Properties["configurationNamingContext"].Value?.ToString();
                        if (string.IsNullOrEmpty(configPath))
                        {
                            Logger.LogWarning("Failed to retrieve configurationNamingContext from RootDSE.");
                            return null;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogWarning("Failed to get configurationNamingContext from RootDSE: {0}", ex.Message);
                    return null;
                }

                string ldapPath = $"LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,{configPath}";
                Logger.LogDebug("Using LDAP path for template query: {0}", ldapPath);

                // Connect to AD using ADSI
                using (var entry = new DirectoryEntry(ldapPath))
                {
                    entry.AuthenticationType = AuthenticationTypes.Secure;
                    foreach (DirectoryEntry child in entry.Children)
                    {
                        string? oid = child.Properties["msPKI-Cert-Template-OID"].Value?.ToString();
                        if (oid == templateOID)
                        {
                            string? displayName = child.Properties["displayName"].Value?.ToString();
                            if (!string.IsNullOrEmpty(displayName))
                            {
                                TemplateNameCache[templateOID] = displayName; // Cache the result
                                Logger.LogDebug("AD template name retrieved for OID {0}: {1}", templateOID, displayName);
                                return displayName;
                            }
                        }
                    }
                    Logger.LogWarning("No template found in AD for OID: {0}", templateOID);
                }
            }
            catch (Exception ex)
            {
                Logger.LogWarning("Failed to query AD for template name, OID: {0}, Error: {1}", templateOID, ex.Message);
            }
            return null;
        }

        protected override void Notify(CertServerModule certServer, ExitEvents exitEvent, Int32 context)
        {
            if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::Notify called");
            Logger.LogInformation("Exit Notify called. Event: {0}, Context: {1}", exitEvent.ToString(), context);

            CertDbRow? props = null;
            try
            {
                switch (exitEvent)
                {
                    case ExitEvents.CertIssued:
                    case ExitEvents.CertUnrevoked:
                    case ExitEvents.CertImported:
                        props = certServer.GetIssuedProperties();
                        foreach (KeyValuePair<string, object?> keyPair in props)
                        {
                            Logger.LogInformation($"{keyPair.Key}: {keyPair.Value}");
                        }
                        SendToApi(props, certServer, context, exitEvent);
                        break;
                    case ExitEvents.CertRevoked:
                        props = certServer.GetRevokedProperties();
                        foreach (KeyValuePair<string, object?> keyPair in props)
                        {
                            Logger.LogInformation($"{keyPair.Key}: {keyPair.Value}");
                        }
                        SendToApi(props, certServer, context, exitEvent);
                        break;
                    case ExitEvents.CertPending:
                    case ExitEvents.CertDenied:
                        props = certServer.GetPendingOrFailedProperties();
                        foreach (KeyValuePair<string, object?> keyPair in props)
                        {
                            Logger.LogInformation($"{keyPair.Key}: {keyPair.Value}");
                        }
                        SendToApi(props, certServer, context, exitEvent);
                        break;
                    default:
                        Logger.LogInformation("No action taken for event: {0}", exitEvent.ToString());
                        break;
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Error in Notify: {0}, Context: {1}, StackTrace: {2}", ex.Message, context, ex.StackTrace);
                if (props != null && props.ContainsKey("SerialNumber"))
                {
                    var filePath = Path.Combine(_bufferDir!, $"{props["SerialNumber"]}.json");
                    var json = JsonConvert.SerializeObject(new { Data = props, SANS = new List<object>(), SubjectAttributes = new List<object>() }, Formatting.Indented);
                    File.WriteAllText(filePath, json);
                    EventLog.WriteEntry("PKIExitModule", $"Error in Notify, data buffered for SerialNumber {props["SerialNumber"]}", EventLogEntryType.Error, 1002);
                }
            }
            finally
            {
                Logger.LogInformation("[END] Context: {0} - Notify completed", context);
                props = null;
                GC.Collect();
                Logger.LogInformation("Cleanup completed for Context: {0}, CertServer released: {1}", context, Marshal.IsComObject(certServer) ? "Yes" : "No");
            }
        }

        private void SendToApi(CertDbRow props, CertServerModule certServer, int context, ExitEvents exitEvent)
        {
            if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::SendToApi called for Context: {0}, Event: {1}", context, exitEvent.ToString());

            // Map Request_Disposition to numeric value
            long? disposition = null;
            if (props.ContainsKey("Request_Disposition"))
            {
                var dispositionValue = props["Request_Disposition"];
                if (dispositionValue is long longValue)
                {
                    // Direct numeric value from props
                    var validDispositions = new HashSet<long> { 8, 9, 12, 15, 16, 17, 20, 21, 30, 31 };
                    if (validDispositions.Contains(longValue))
                    {
                        disposition = longValue;
                    }
                    else
                    {
                        Logger.LogError("Invalid Request_Disposition value: {0}, buffering data for Context: {1}", longValue, context);
                        BufferJson(new { Data = props, SANS = new List<object>(), SubjectAttributes = new List<object>() }, context, props);
                        return;
                    }
                }
                else
                {
                    // Handle string/enum case (from log: "Issued", "Revoked", etc.)
                    string? dispositionStr = dispositionValue?.ToString();
                    switch (dispositionStr)
                    {
                        case "Issued": disposition = 20; break;
                        case "Revoked": disposition = 21; break;
                        case "Denied": disposition = 9; break;
                        case "Pending": disposition = 15; break;
                        case "Unrevoked": disposition = 20; break;
                        case "Imported": disposition = 20; break;
                        default:
                            Logger.LogError("Unknown Request_Disposition string: {0}, buffering data for Context: {1}", dispositionStr, context);
                            BufferJson(new { Data = props, SANS = new List<object>(), SubjectAttributes = new List<object>() }, context, props);
                            return;
                    }
                }
            }
            else
            {
                Logger.LogError("Request_Disposition missing for Context: {0}, buffering data", context);
                BufferJson(new { Data = props, SANS = new List<object>(), SubjectAttributes = new List<object>() }, context, props);
                return;
            }

            // Build SubjectAttributes from props
            var subjectAttributes = new List<object>();
            var subjectKeys = new[]
            {
                "Request_CommonName", "Request_Organization", "Request_OrgUnit", "Request_Locality",
                "Request_State", "Request_Country", "Request_EMail", "Request_StreetAddress",
                "Request_UnstructuredName", "Request_UnstructuredAddress", "Request_DeviceSerialNumber"
            };
            foreach (var key in subjectKeys)
            {
                if (props.ContainsKey(key))
                {
                    string? value = props[key]?.ToString();
                    if (!string.IsNullOrEmpty(value))
                    {
                        subjectAttributes.Add(new
                        {
                            attributeType = key.Replace("Request_", ""),
                            attributeValue = value
                        });
                    }
                }
            }
            Logger.LogDebug("SubjectAttributes generated: {0}", JsonConvert.SerializeObject(subjectAttributes, Formatting.Indented));

            // Get TemplateName from AD
            string templateName = "UnknownTemplate";
            try
            {
                var templateOID = props.ContainsKey("CertificateTemplate") ? props["CertificateTemplate"]?.ToString() : null;
                templateName = GetTemplateNameFromAD(templateOID) ?? certServer.GetCertificateTemplate() ?? "UnknownTemplate";
                Logger.LogDebug("TemplateName retrieved: {0}", templateName);
            }
            catch (Exception ex)
            {
                Logger.LogWarning("Failed to get CertificateTemplate: {0}", ex.Message);
            }

            // Build SANS (original tested code)
            var sansList = new List<object>();
            if (props.ContainsKey("RawCertificate") && props["RawCertificate"] != null)
            {
                if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::Notify Processing RawCertificate for Context: {0}", context);
                var rawCertValue = props["RawCertificate"];
                if (rawCertValue is byte[] certData)
                {
                    if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::Notify RawCertificate is Byte[], length: {0} for Context: {1}", certData.Length, context);
                    var cert = new X509Certificate2(certData);
                    if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::Notify X509Certificate2 successfully initialized for Context: {0}", context);
                    var extensions = cert.Extensions;
                    if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::Notify Extensions retrieved for Context: {0}, Count: {1}", context, extensions.Count);
                    var sanExtension = extensions.Cast<X509Extension>().FirstOrDefault(e => e.Oid.Value == "2.5.29.17");
                    if (sanExtension != null)
                    {
                        if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::Notify SAN extension found for Context: {0}", context);
                        var asnEncodedData = new AsnEncodedData(sanExtension.Oid, sanExtension.RawData);
                        var san = new X509SubjectAlternativeNamesExtension(asnEncodedData, sanExtension.Critical);
                        if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::Notify SAN extension parsed, count: {0} for Context: {1}", san.AlternativeNames.Count, context);
                        foreach (var altName in san.AlternativeNames)
                        {
                            try
                            {
                                string sanType = altName.Type.ToString().ToLower();
                                string oid = altName.OID?.Value ?? "";
                                string value = altName.Value ?? "null";
                                sansList.Add(new { SANSType = sanType, OID = oid, Value = value });
                                if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::Notify Processed SAN: {0}, OID: {1}, Value: {2}", sanType, oid, value);
                            }
                            catch (Exception ex)
                            {
                                Logger.LogWarning("Error processing SAN item for Context: {0}, Error: {1}", context, ex.Message);
                            }
                        }
                    }
                    else if (Logger.LogLevel <= LogLevel.Debug)
                    {
                        Logger.LogDebug("Exit::Notify No Subject Alternative Names found in certificate for Context: {0}", context);
                    }
                }
                else if (Logger.LogLevel <= LogLevel.Debug)
                {
                    Logger.LogWarning("Exit::Notify RawCertificate is not Byte[] for Context: {0}, Type: {1}", context, rawCertValue?.GetType().Name ?? "null");
                }
            }

            // Build JSON payload
            var payload = new
            {
                data = new
                {
                    caId = Environment.MachineName.ToUpper(),
                    issuerName = _caName ?? "Unknown CA",
                    serialNumber = props.ContainsKey("SerialNumber") ? props["SerialNumber"]?.ToString() : null,
                    request_RequestID = props.ContainsKey("Request_RequestID") ? TryParseLong(props["Request_RequestID"]) : null,
                    disposition,
                    submittedWhen = props.ContainsKey("Request_SubmittedWhen") ? ((DateTime?)props["Request_SubmittedWhen"])?.ToString("o") : null,
                    notBefore = props.ContainsKey("NotBefore") ? ((DateTime?)props["NotBefore"])?.ToString("o") : null,
                    notAfter = props.ContainsKey("NotAfter") ? ((DateTime?)props["NotAfter"])?.ToString("o") : null,
                    templateOID = props.ContainsKey("CertificateTemplate") ? props["CertificateTemplate"]?.ToString() : null,
                    templateName,
                    keyRecoveryHashes = props.ContainsKey("Request_KeyRecoveryHashes") ? props["Request_KeyRecoveryHashes"]?.ToString() ?? "" : "",
                    signerApplicationPolicies = props.ContainsKey("Request_SignerApplicationPolicies") ? props["Request_SignerApplicationPolicies"]?.ToString() : null,
                    // Optional fields
                    requesterName = props.ContainsKey("Request_RequesterName") ? props["Request_RequesterName"]?.ToString() : null,
                    callerName = props.ContainsKey("Request_CallerName") ? props["Request_CallerName"]?.ToString() : null,
                    subjectKeyIdentifier = props.ContainsKey("SubjectKeyIdentifier") ? props["SubjectKeyIdentifier"]?.ToString() : null,
                    thumbprint = props.ContainsKey("CertificateHash") ? props["CertificateHash"]?.ToString() : null,
                    publicKeyLength = props.ContainsKey("PublicKeyLength") ? props["PublicKeyLength"]?.ToString() : null,
                    publicKeyAlgorithm = props.ContainsKey("PublicKeyAlgorithm") ? props["PublicKeyAlgorithm"]?.ToString() : null,
                    dispositionMessage = props.ContainsKey("Request_DispositionMessage") ? props["Request_DispositionMessage"]?.ToString() : null,
                    // Optional fields from schema
                    requestType = props.ContainsKey("RequestType") ? TryParseLong(props["RequestType"]) : null,
                    requestFlags = props.ContainsKey("RequestFlags") ? props["RequestFlags"]?.ToString() : null,
                    statusCode = props.ContainsKey("Request_StatusCode") ? TryParseLong(props["Request_StatusCode"]) : null,
                    signerPolicies = props.ContainsKey("Request_SignerPolicies") ? props["Request_SignerPolicies"]?.ToString() : null,
                    // Revocation fields (mandatory for CertRevoked)
                    revokedWhen = props.ContainsKey("Request_RevokedWhen") ? ((DateTime?)props["Request_RevokedWhen"])?.ToString("o") : null,
                    revokedEffectiveWhen = props.ContainsKey("Request_RevokedEffectiveWhen") ? ((DateTime?)props["Request_RevokedEffectiveWhen"])?.ToString("o") : null,
                    revokedReason = props.ContainsKey("Request_RevokedReason") ? TryParseLong(props["Request_RevokedReason"]) : null
                },
                sans = sansList,
                subjectAttributes
            };

            // Validate required fields
            var missingFields = new List<string>();
            if (string.IsNullOrEmpty(payload.data.caId)) missingFields.Add("caId");
            if (string.IsNullOrEmpty(payload.data.issuerName)) missingFields.Add("issuerName");
            if (string.IsNullOrEmpty(payload.data.serialNumber)) missingFields.Add("serialNumber");
            if (payload.data.request_RequestID == null) missingFields.Add("request_RequestID");
            if (payload.data.disposition == null) missingFields.Add("disposition");
            if (payload.data.submittedWhen == null) missingFields.Add("submittedWhen");
            if (payload.data.notBefore == null) missingFields.Add("notBefore");
            if (payload.data.notAfter == null) missingFields.Add("notAfter");
            if (string.IsNullOrEmpty(payload.data.templateOID)) missingFields.Add("templateOID");
            if (string.IsNullOrEmpty(payload.data.templateName)) missingFields.Add("templateName");
            if (payload.data.keyRecoveryHashes == null) missingFields.Add("keyRecoveryHashes");
            if (string.IsNullOrEmpty(payload.data.signerApplicationPolicies)) missingFields.Add("signerApplicationPolicies");

            // Additional validation for CertRevoked
            if (exitEvent == ExitEvents.CertRevoked)
            {
                if (payload.data.revokedWhen == null) missingFields.Add("revokedWhen");
                if (payload.data.revokedEffectiveWhen == null) missingFields.Add("revokedEffectiveWhen");
                if (payload.data.revokedReason == null) missingFields.Add("revokedReason");
            }

            if (missingFields.Count > 0)
            {
                Logger.LogError("Missing required fields for Context {0}: {1}, buffering data", context, string.Join(", ", missingFields));
                BufferJson(payload, context, props);
                return;
            }

            // Serialize JSON with camelCase
            var jsonSettings = new JsonSerializerSettings
            {
                ContractResolver = new CamelCasePropertyNamesContractResolver(),
                Formatting = Formatting.Indented
            };
            string json = JsonConvert.SerializeObject(payload, jsonSettings);
            Logger.LogDebug("Generated JSON for Context {0}: {1}", context, json);

            // Send to API
            try
            {
                using (var client = new HttpClient())
                {
                    if (!string.IsNullOrEmpty(_apiKey))
                    {
                        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _apiKey);
                    }
                    var content = new StringContent(json, Encoding.UTF8, "application/json");
                    var response = client.PostAsync(_apiUrl, content).Result;
                    if (response.IsSuccessStatusCode)
                    {
                        Logger.LogInformation("API call successful for Context {0}, SerialNumber: {1}", context, payload.data.serialNumber);
                        EventLog.WriteEntry("PKIExitModule", $"API call successful for SerialNumber {payload.data.serialNumber}", EventLogEntryType.Information, 1000);
                    }
                    else
                    {
                        var responseBody = response.Content.ReadAsStringAsync().Result;
                        Logger.LogError("API call failed for Context {0}, Status: {1}, Response: {2}", context, response.StatusCode, responseBody);
                        BufferJson(payload, context, props);
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Error sending to API for Context: {0}, Error: {1}, StackTrace: {2}", context, ex.Message, ex.StackTrace);
                BufferJson(payload, context, props);
            }
        }

        private void BufferJson(object payload, int context, CertDbRow? props)
        {
            try
            {
                var jsonSettings = new JsonSerializerSettings { Formatting = Formatting.Indented };
                string json = JsonConvert.SerializeObject(payload, jsonSettings);
                var filePath = Path.Combine(_bufferDir!, $"Notify_{context}_{DateTime.Now:yyyyMMdd_HHmmss}.json");
                File.WriteAllText(filePath, json);
                Logger.LogInformation("JSON file buffered to: {0}", filePath);
                if (props != null && props.ContainsKey("SerialNumber"))
                {
                    var serialPath = Path.Combine(_bufferDir!, $"{props["SerialNumber"]}.json");
                    File.WriteAllText(serialPath, json);
                    Logger.LogInformation("JSON also buffered with SerialNumber: {0}", props["SerialNumber"]);
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Error buffering JSON for Context: {0}, Error: {1}", context, ex.Message);
            }
        }

        private long? TryParseLong(object value)
        {
            if (value == null || value == DBNull.Value) return null;
            try
            {
                return Convert.ToInt64(value);
            }
            catch (Exception ex)
            {
                Logger.LogWarning("Cannot cast {0} to long. Value: {1}, Error: {2}", value.GetType().Name, value, ex.Message);
                return null;
            }
        }

        public override string GetDescription()
        {
            if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::GetDescription called.");
            return "PKI Exit Module for ADCS";
        }

        public override ICertManageModule GetManageModule()
        {
            if (Logger.LogLevel <= LogLevel.Debug) Logger.LogDebug("Exit::GetManageModule called.");
            return new ExitManage(Logger);
        }
    }
}