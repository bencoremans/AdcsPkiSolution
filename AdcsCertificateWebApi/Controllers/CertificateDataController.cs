using System;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using System.Security.Cryptography;
using System.Text;
using Serilog;

namespace AdcsCertificateApi
{
    [Route("api/[controller]")]
    [ApiController]
    public class CertificateDataController : ControllerBase
    {
        private readonly AuthDbContext dbContext;
        private readonly ILogger<CertificateDataController> logger;

        public CertificateDataController(AuthDbContext dbContext, ILogger<CertificateDataController> logger)
        {
            this.dbContext = dbContext;
            this.logger = logger;
        }

        private void MapCertificateDataToLog(CertificateLogDto source, CertificateLog target, bool isUpdate = false, long templateId = 0)
        {
            if (!isUpdate)
            {
                // Full mapping for new records
                target.AdcsServerName = source.AdcsServerName;  // Renamed from AdcsServerName
                target.SerialNumber = source.SerialNumber;
                target.Request_RequestID = source.Request_RequestID;
                target.Disposition = source.Disposition;
                target.SubmittedWhen = source.SubmittedWhen;
                target.ResolvedWhen = source.ResolvedWhen;
                target.RequesterName = source.RequesterName;
                target.CallerName = source.CallerName;
                target.NotBefore = source.NotBefore;
                target.NotAfter = source.NotAfter;
                target.SubjectKeyIdentifier = source.SubjectKeyIdentifier;
                target.Thumbprint = source.Thumbprint;
                target.TemplateID = templateId;
                target.RequestType = source.RequestType;
                target.RequestFlags = source.RequestFlags;
                target.StatusCode = source.StatusCode;
                target.DispositionMessage = source.DispositionMessage;
                target.SignerPolicies = source.SignerPolicies;
                target.SignerApplicationPolicies = source.SignerApplicationPolicies;
                target.Officer = source.Officer;
                target.KeyRecoveryHashes = source.KeyRecoveryHashes;
                target.EnrollmentFlags = source.EnrollmentFlags;
                target.GeneralFlags = source.GeneralFlags;
                target.PrivateKeyFlags = source.PrivateKeyFlags;
                target.PublishExpiredCertInCRL = source.PublishExpiredCertInCRL;
                target.PublicKeyLength = source.PublicKeyLength;
                target.PublicKeyAlgorithm = source.PublicKeyAlgorithm;
                target.RevokedWhen = source.RevokedWhen;
                target.RevokedEffectiveWhen = source.RevokedEffectiveWhen;
                target.RevokedReason = source.RevokedReason;
            }
            else
            {
                // Specific updates based on Disposition
                target.Disposition = source.Disposition;
                target.StatusCode = source.StatusCode;
                target.DispositionMessage = source.DispositionMessage;

                if (source.Disposition == 30) // Renewal
                {
                    target.NotAfter = source.NotAfter;
                }
                else if (source.Disposition == 31) // Key recovery
                {
                    target.KeyRecoveryHashes = source.KeyRecoveryHashes;
                }
                else if (source.Disposition == 21) // Revocation
                {
                    target.RevokedWhen = source.RevokedWhen;
                    target.RevokedEffectiveWhen = source.RevokedEffectiveWhen;
                    target.RevokedReason = source.RevokedReason;
                }
            }
        }

        [HttpPost]
        public async Task<IActionResult> StoreCertificateData([FromBody] CertificateDataDto certificateData)
        {
            if (!ModelState.IsValid)
            {
                var errors = ModelState.SelectMany(x => x.Value.Errors.Select(e => new { Field = x.Key, Error = e.ErrorMessage })).ToList();
                logger.LogError("Model validation errors for POST /api/CertificateData: {Errors}", string.Join("; ", errors.Select(e => $"Field: {e.Field}, Error: {e.Error}")));
                return BadRequest(new { Errors = errors });
            }

            if (certificateData == null || certificateData.Data == null)
            {
                logger.LogError("Invalid JSON body received: certificateData or certificateData.Data is null");
                return BadRequest("JSON body is null or invalid");
            }

            // Validate allowed Disposition values
            var validDispositions = new[] { 8, 9, 12, 15, 16, 17, 20, 21, 30, 31 };
            if (!validDispositions.Any(d => d == certificateData.Data.Disposition))
            {
                logger.LogError("Invalid Disposition value: {Disposition}, SerialNumber: {SerialNumber}", certificateData.Data.Disposition, certificateData.Data.SerialNumber);
                return BadRequest($"Invalid Disposition value: {certificateData.Data.Disposition}. Valid values are: {string.Join(", ", validDispositions)}");
            }

            // Validate revocation-specific fields
            if (certificateData.Data.Disposition == 21)
            {
                var validationErrors = new List<string>();
                if (certificateData.Data.RevokedWhen == null)
                    validationErrors.Add("RevokedWhen is required for revocation");
                if (certificateData.Data.RevokedEffectiveWhen == null)
                    validationErrors.Add("RevokedEffectiveWhen is required for revocation");
                if (certificateData.Data.RevokedReason == null)
                    validationErrors.Add("RevokedReason is required for revocation");

                if (validationErrors.Any())
                {
                    logger.LogError("Validation errors for revocation, SerialNumber: {SerialNumber}: {Errors}", certificateData.Data.SerialNumber, string.Join("; ", validationErrors));
                    return BadRequest(new { Errors = validationErrors });
                }
            }

            logger.LogInformation("Testing database connection for SerialNumber: {SerialNumber}", certificateData.Data.SerialNumber);
            var conn = dbContext.Database.GetDbConnection();
            if (conn == null)
            {
                logger.LogError("Database connection object is null for SerialNumber: {SerialNumber}", certificateData.Data.SerialNumber);
                return StatusCode(503, "Database connection object not available");
            }

            try
            {
                if (conn.State == ConnectionState.Closed)
                {
                    await conn.OpenAsync();
                    logger.LogInformation("Database connection opened for SerialNumber: {SerialNumber}", certificateData.Data.SerialNumber);
                }
            }
            catch (Exception connEx)
            {
                logger.LogError(connEx, "Error opening database connection for SerialNumber: {SerialNumber}", certificateData.Data.SerialNumber);
                return StatusCode(503, $"Database connection test failed: {connEx.Message}");
            }
            finally
            {
                if (conn.State == ConnectionState.Open)
                {
                    conn.Close();
                    logger.LogDebug("Database connection closed after test for SerialNumber: {SerialNumber}", certificateData.Data.SerialNumber);
                }
            }

            try
            {
                // Check if template exists
                var template = await dbContext.CertificateTemplates
                    .FirstOrDefaultAsync(t => t.TemplateOID == certificateData.Data.TemplateOID);
                if (template == null)
                {
                    template = new CertificateTemplate
                    {
                        TemplateName = certificateData.Data.TemplateName,
                        TemplateOID = certificateData.Data.TemplateOID
                    };
                    dbContext.CertificateTemplates.Add(template);
                    await dbContext.SaveChangesAsync();
                    logger.LogInformation("New template added: {TemplateName} (OID: {TemplateOID})", template.TemplateName, template.TemplateOID);
                }

                // Check if CA exists (updated to AdcsServerName)
                var ca = await dbContext.CAs.FirstOrDefaultAsync(c => c.AdcsServerName == certificateData.Data.AdcsServerName);  // Renamed
                if (ca == null)
                {
                    ca = new CA { AdcsServerName = certificateData.Data.AdcsServerName, IssuerName = certificateData.Data.IssuerName };  // Renamed
                    dbContext.CAs.Add(ca);
                    await dbContext.SaveChangesAsync();
                    logger.LogInformation("New CA added: {AdcsServerName}, IssuerName: {IssuerName}", ca.AdcsServerName, ca.IssuerName);
                }

                // Check if CertificateLog already exists (unique on AdcsServerName + SerialNumber)
                var existingLog = await dbContext.CertificateLogs
                    .FirstOrDefaultAsync(l => l.AdcsServerName == certificateData.Data.AdcsServerName && l.SerialNumber == certificateData.Data.SerialNumber);

                long certificateId;
                if (existingLog == null)
                {
                    // Create new log
                    var newLog = new CertificateLog();
                    MapCertificateDataToLog(certificateData.Data, newLog, templateId: template.TemplateID);
                    dbContext.CertificateLogs.Add(newLog);
                    await dbContext.SaveChangesAsync();
                    certificateId = newLog.CertificateID;
                    logger.LogInformation("New CertificateLog created for SerialNumber: {SerialNumber}, CertificateID: {CertificateID}", certificateData.Data.SerialNumber, certificateId);
                }
                else
                {
                    // Check for duplicate based on Disposition
                    if (existingLog.Disposition == certificateData.Data.Disposition)
                    {
                        logger.LogInformation("No changes detected for SerialNumber: {SerialNumber}. No update performed.", certificateData.Data.SerialNumber);
                        return Conflict($"Certificate with SerialNumber {certificateData.Data.SerialNumber} and AdcsServerName {certificateData.Data.AdcsServerName} already exists with the same Disposition ({existingLog.Disposition}).");
                    }

                    // Update existing record with specific fields
                    MapCertificateDataToLog(certificateData.Data, existingLog, isUpdate: true, templateId: template.TemplateID);
                    dbContext.CertificateLogs.Update(existingLog);
                    await dbContext.SaveChangesAsync();
                    certificateId = existingLog.CertificateID;
                    logger.LogInformation("CertificateLog updated for SerialNumber: {SerialNumber}", certificateData.Data.SerialNumber);
                }

                // Subject attributes
                if (certificateData.SubjectAttributes != null && certificateData.SubjectAttributes.Any())
                {
                    var attributes = certificateData.SubjectAttributes
                        .Where(a => !string.IsNullOrEmpty(a.AttributeValue))
                        .Select(a => new SubjectAttribute
                        {
                            CertificateID = certificateId,
                            AttributeType = a.AttributeType,
                            AttributeValue = a.AttributeValue,
                            AttributeValueHash = ComputeSHA256(a.AttributeValue)
                        }).ToList();
                    dbContext.SubjectAttributes.AddRange(attributes);
                    logger.LogInformation("Adding {0} subject attributes for SerialNumber: {1}", attributes.Count, certificateData.Data.SerialNumber);
                }

                // SANs
                if (certificateData.SANS != null && certificateData.SANS.Any())
                {
                    var validSANS = certificateData.SANS
                        .Where(s => !string.IsNullOrEmpty(s.SANSType) && !string.IsNullOrEmpty(s.Value))
                        .Select(s => new CertificateSan
                        {
                            CertificateID = certificateId,
                            SANSValue = s.Value,
                            SANSType = s.SANSType
                        }).ToList();

                    // Check for existing SANs to avoid duplicates
                    foreach (var san in validSANS)
                    {
                        var exists = await dbContext.CertificateSANS
                            .AnyAsync(s => s.CertificateID == san.CertificateID && s.SANSValue == san.SANSValue && s.SANSType == san.SANSType);
                        if (!exists)
                        {
                            dbContext.CertificateSANS.Add(san);
                        }
                    }
                    logger.LogInformation("Adding {0} SANs for SerialNumber: {1}", validSANS.Count, certificateData.Data.SerialNumber);
                }

                await dbContext.SaveChangesAsync();
                logger.LogInformation("Certificate data stored successfully for SerialNumber: {SerialNumber}", certificateData.Data.SerialNumber);
                return Ok("Certificate data stored successfully");
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error saving certificate data for SerialNumber: {SerialNumber}", certificateData.Data.SerialNumber);
                return StatusCode(500, $"Error saving: {ex.Message}");
            }
        }

        private static byte[] ComputeSHA256(string input)
        {
            if (string.IsNullOrEmpty(input))
            {
                return Array.Empty<byte>();
            }
            using (var sha256 = SHA256.Create())
            {
                return sha256.ComputeHash(Encoding.UTF8.GetBytes(input));
            }
        }
    }
}