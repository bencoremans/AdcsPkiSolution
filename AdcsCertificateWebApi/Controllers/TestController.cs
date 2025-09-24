using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using System.Linq;

namespace AdcsCertificateApi
{
    [Route("api/[controller]")]
    [ApiController]
    public class TestController : ControllerBase
    {
        private readonly ILogger<TestController> logger;

        public TestController(ILogger<TestController> logger)
        {
            this.logger = logger;
        }

        [HttpGet]
        public IActionResult Get()
        {
            return Ok("Test endpoint werkt");
        }

        [HttpPost("validate")]
        public IActionResult ValidateCertificateData([FromBody] CertificateDataDto certificateData)
        {
            if (!ModelState.IsValid)
            {
                var errors = ModelState
                    .SelectMany(x => x.Value.Errors.Select(e => new { Field = x.Key, Error = e.ErrorMessage }))
                    .ToList();
                var errorMessages = errors.Select(e => $"Veld: {e.Field}, Fout: {e.Error}");
                logger.LogError("Modelvalidatiefouten voor POST /api/Test/validate: {Errors}", string.Join("; ", errorMessages));
                return BadRequest(new { Errors = errors.Select(e => new { e.Field, e.Error }) });
            }

            logger.LogInformation("JSON-body validatie geslaagd");
            return Ok("JSON-body is geldig");
        }
    }
}