using System;
using System.Runtime.InteropServices;
using ADCS.CertMod.Managed;

namespace ADCS.CertMod
{
    [ComVisible(true)]
    [ClassInterface(ClassInterfaceType.None)]
    [ProgId("AdcsExitModule.ExitManage")]
    [Guid("434350aa-7cdf-4c78-9973-8f51bf320365")]
    public class ExitManage : ICertManageModule
    {
        private readonly ILogWriter? _logWriter;

        public ExitManage(ILogWriter logger)
        {
            _logWriter = logger;
            _logWriter?.LogDebug("ExitManage constructor called.");
        }

        public object GetProperty(string strConfig, string strStorageLocation, string strPropertyName, int Flags)
        {
            _logWriter?.LogDebug("ExitManage.GetProperty called with Config: {0}, Storage: {1}, Property: {2}, Flags: {3}", strConfig, strStorageLocation, strPropertyName, Flags);
            switch (strPropertyName.ToLower())
            {
                case "name":
                    return "PKI Exit Module";
                case "description":
                    return "PKI exit module for ADCS.";
                case "copyright":
                    return "Copyright (c) 2025, Justitiele ICT Organisatie";
                case "file version":
                    return "0.2";
                case "product version":
                    return "0.2.1";
                default:
                    _logWriter?.LogWarning("Unknown property requested: {0}", strPropertyName);
                    return $"Unknown Property: {strPropertyName}";
            }
        }

        public void SetProperty(string strConfig, string strStorageLocation, string strPropertyName, int Flags, ref object pvarProperty)
        {
            _logWriter?.LogDebug("ExitManage.SetProperty called with Config: {0}, Storage: {1}, Property: {2}, Flags: {3}, Value: {4}", strConfig, strStorageLocation, strPropertyName, Flags, pvarProperty);
            // No writable properties implemented; log and ignore
            _logWriter?.LogWarning("SetProperty not supported for property: {0}", strPropertyName);
        }

        public void Configure(string strConfig, string strStorageLocation, int Flags)
        {
            _logWriter?.LogDebug("ExitManage.Configure called with Config: {0}, Storage: {1}, Flags: {2}", strConfig, strStorageLocation, Flags);
            // No UI configuration implemented; log and return
            _logWriter?.LogInformation("Configure called but no UI configuration implemented for this module.");
        }
    }
}