using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace AdcsCertificateApi
{
    [Route("api/[controller]")]
    [ApiController]
    public class CertificatesController : ControllerBase
    {
        private readonly AuthDbContext dbContext;
        private readonly ILogger<CertificatesController> logger;

        public CertificatesController(AuthDbContext dbContext, ILogger<CertificatesController> logger)
        {
            this.dbContext = dbContext;
            this.logger = logger;
        }

        [HttpGet("expiring")]
        public async Task<IActionResult> GetExpiringCertificates()
        {
            try
            {
                var expiring = await dbContext.CertificateLogs
                    .Where(c => c.NotAfter < DateTime.Now.AddDays(30) && c.Disposition == 20)
                    .ToListAsync();
                logger.LogInformation("Expirerende certificaten opgehaald. Aantal: {Count}", expiring.Count);
                return Ok(expiring);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Fout bij ophalen van expirerende certificaten");
                return StatusCode(500, $"Fout bij ophalen: {ex.Message}");
            }
        }
    }
}