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
            return Ok("Test endpoint works");
        }

        [HttpPost("validate")]
        public IActionResult ValidateCertificateData([FromBody] CertificateDataDto certificateData)
        {
            if (!ModelState.IsValid)
            {
                var errors = ModelState
                    .SelectMany(x => x.Value.Errors.Select(e => new { Field = x.Key, Error = e.ErrorMessage }))
                    .ToList();
                var errorMessages = errors.Select(e => $"Field: {e.Field}, Error: {e.Error}");
                logger.LogError("Model validation errors for POST /api/Test/validate: {Errors}", string.Join("; ", errorMessages));
                return BadRequest(new { Errors = errors.Select(e => new { e.Field, e.Error }) });
            }

            logger.LogInformation("JSON body validation successful");
            return Ok("JSON body is valid");
        }
    }
}