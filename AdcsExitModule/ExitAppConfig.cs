using System;
using System.Security.Cryptography;
using System.Text;
using ADCS.CertMod.Managed;
using Microsoft.Win32;

namespace ADCS.CertMod
{
    public class ExitAppConfig : RegistryService
    {
        // Constants for registry key names
        public const string PROP_LOG_LEVEL = "LogLevel";
        private const string REG_API_URL = "ApiUrl";
        private const string REG_API_KEY_ENCRYPTED = "ApiKeyEncrypted";
        private const string REG_BUFFER_DIR = "BufferDir";
        private const string REG_LOG_BASE_DIR = "LogBaseDir";

        private readonly ILogWriter _logger; // Field to store the logger instance for logging operations

        // Constructor: Initializes the base RegistryService with module name and type, and sets up the logger
        public ExitAppConfig(string moduleName, ILogWriter logWriter) : base(moduleName, CertServerModuleType.Exit)
        {
            _logger = logWriter ?? throw new ArgumentNullException(nameof(logWriter), "LogWriter cannot be null.");
            _logger.LogDebug("ExitAppConfig initialized with module name: {0}", moduleName);
        }

        // Initializes configuration by verifying required registry values exist
        public bool InitializeConfig()
        {
            try
            {
                _logger.LogDebug("Starting configuration initialization.");
                var apiUrl = GetRecord(REG_API_URL);
                var apiKey = GetRecord(REG_API_KEY_ENCRYPTED);
                var bufferDir = GetRecord(REG_BUFFER_DIR);
                var logBaseDir = GetRecord(REG_LOG_BASE_DIR);

                if (apiUrl == null || apiKey == null || bufferDir == null || logBaseDir == null)
                {
                    _logger.LogWarning("One or more required registry values are missing: ApiUrl, ApiKeyEncrypted, BufferDir, or LogBaseDir.");
                    return false;
                }
                _logger.LogDebug("Configuration initialized successfully from registry.");
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError("Error initializing configuration: {0}, StackTrace: {1}", ex.Message, ex.StackTrace);
                return false;
            }
        }

        // Retrieves the API URL from the registry, returns empty string if not found
        public string GetApiUrl()
        {
            _logger.LogDebug("Retrieving API URL from registry.");
            var triplet = GetRecord(REG_API_URL);
            return triplet?.Value?.ToString() ?? string.Empty;
        }

        // Retrieves and decrypts the API key from the registry, returns empty string on failure
        public string GetApiKey()
        {
            _logger.LogDebug("Retrieving and decrypting API key from registry.");
            var triplet = GetRecord(REG_API_KEY_ENCRYPTED);
            if (triplet?.Value != null)
            {
                try
                {
                    byte[] encryptedData = Convert.FromBase64String(triplet.Value.ToString());
                    _logger.LogDebug("API key decryption started for encrypted data length: {0}", encryptedData.Length);
                    byte[] decryptedData = ProtectedData.Unprotect(encryptedData, null, DataProtectionScope.LocalMachine);
                    return Encoding.UTF8.GetString(decryptedData);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning("Failed to decrypt API key: {0}", ex.Message);
                    return string.Empty;
                }
            }
            _logger.LogDebug("No API key found in registry.");
            return string.Empty;
        }

        // Retrieves the buffer directory from the registry, returns empty string if not found
        public string GetBufferDir()
        {
            _logger.LogDebug("Retrieving buffer directory from registry.");
            var triplet = GetRecord(REG_BUFFER_DIR);
            return triplet?.Value?.ToString() ?? string.Empty;
        }

        // Retrieves the log base directory from the registry, returns C:\ as fallback if not specified
        public string GetLogBaseDir()
        {
            _logger.LogDebug("Retrieving log base directory from registry.");
            var triplet = GetRecord(REG_LOG_BASE_DIR);
            return triplet?.Value?.ToString() ?? @"C:\"; // Fallback to C:\ if not specified
        }

        #region LogLevel
        // Retrieves the log level from the registry, defaults to Information (3) for production safety
        public LogLevel GetLogLevel()
        {
            _logger.LogDebug("Retrieving log level from registry.");
            try
            {
                RegTriplet? triplet = GetRecord(PROP_LOG_LEVEL);
                if (triplet?.Type == RegistryValueKind.DWord && triplet.Value != null)
                {
                    int levelValue = (int)triplet.Value;
                    _logger.LogDebug("Log level found in registry as DWord, value: {0}", levelValue);
                    switch (levelValue)
                    {
                        case 0: return LogLevel.None;
                        case 1: return LogLevel.Trace;
                        case 2: return LogLevel.Debug;
                        case 3: return LogLevel.Information;
                        case 4: return LogLevel.Warning;
                        case 5: return LogLevel.Error;
                        case 6: return LogLevel.Critical;
                        default: _logger.LogWarning("Unknown log level value {0} in registry, defaulting to Information", levelValue); break;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning("Error retrieving log level from registry: {0}", ex.Message);
            }
            _logger.LogDebug("No valid log level found in registry, using default: Information (3) for production safety");
            return LogLevel.Information; // Default to Information (3) to disable Trace/Debug in production
        }

        // Sets the log level in the registry
        public void SetLogLevel(LogLevel logLevel)
        {
            _logger.LogDebug("Setting log level to: {0}", logLevel);
            WriteRecord(new RegTriplet(PROP_LOG_LEVEL, RegistryValueKind.DWord)
            {
                Value = logLevel
            });
        }
        #endregion
    }
}