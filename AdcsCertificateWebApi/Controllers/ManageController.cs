using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AdcsCertificateApi;
using System;
using System.Threading.Tasks;
using System.Collections.Generic;

namespace AdcsCertificateApi.Controllers
{
    [Authorize(Policy = "KerberosOnly")]  // Use policy instead of scheme. Add to the manual to add SPN for the app pool gmsa account!
    [Route("api/[controller]")]
    [ApiController]
    public class ManageController : ControllerBase
    {
        private readonly AuthDbContext dbContext;

        public ManageController(AuthDbContext dbContext)
        {
            this.dbContext = dbContext;
        }

        // GET /api/Manage/AuthorizedServers
        [HttpGet("AuthorizedServers")]
        public async Task<ActionResult<IEnumerable<AuthorizedServer>>> GetAuthorizedServers()
        {
            var servers = await dbContext.AuthorizedServers.ToListAsync();
            return Ok(servers);
        }

        // GET /api/Manage/AuthorizedServers/{id}
        [HttpGet("AuthorizedServers/{id}")]
        public async Task<ActionResult<AuthorizedServer>> GetAuthorizedServer(long id)
        {
            var server = await dbContext.AuthorizedServers.FindAsync(id);
            if (server == null)
                return NotFound();
            return Ok(server);
        }

        // POST /api/Manage/AuthorizedServers
        [HttpPost("AuthorizedServers")]
        public async Task<ActionResult<AuthorizedServer>> CreateAuthorizedServer(AuthorizedServer server)
        {
            if (!Guid.TryParse(server.ServerGUID, out _))
            {
                return BadRequest("Invalid ServerGUID format. Must be a valid GUID.");
            }

            // Check if AdcsServer exists
            var adcsServer = await dbContext.AuthorizedServers.FindAsync(server.AdcsServerAccount);
            if (adcsServer == null)
            {
                return BadRequest($"AdcsServerName '{server.AdcsServerAccount}' not found.");
            }

            // Check unique constraint
            if (await dbContext.AuthorizedServers.AnyAsync(s => s.AdcsServerAccount == server.AdcsServerAccount && s.ServerGUID == server.ServerGUID))
            {
                return Conflict("Combination of AdcsServerName and ServerGUID already exists.");
            }

            dbContext.AuthorizedServers.Add(server);
            await dbContext.SaveChangesAsync();
            return CreatedAtAction(nameof(GetAuthorizedServer), new { id = server.ServerID }, server);
        }

        // PUT /api/Manage/AuthorizedServers/{id}
        [HttpPut("AuthorizedServers/{id}")]
        public async Task<IActionResult> UpdateAuthorizedServer(long id, AuthorizedServer server)
        {
            if (id != server.ServerID)
                return BadRequest();

            if (!Guid.TryParse(server.ServerGUID, out _))
            {
                return BadRequest("Invalid ServerGUID format. Must be a valid GUID.");
            }

            // Check unique constraint (exclude current)
            if (await dbContext.AuthorizedServers.AnyAsync(s => s.AdcsServerAccount == server.AdcsServerAccount && s.ServerGUID == server.ServerGUID && s.ServerID != id))
            {
                return Conflict("Combination of AdcsServerName and ServerGUID already exists.");
            }

            dbContext.Entry(server).State = EntityState.Modified;
            try
            {
                await dbContext.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!await AuthorizedServerExists(id))
                    return NotFound();
                throw;
            }
            return NoContent();
        }

        // DELETE /api/Manage/AuthorizedServers/{id} (soft delete: set IsActive = false)
        [HttpDelete("AuthorizedServers/{id}")]
        public async Task<IActionResult> DeleteAuthorizedServer(long id)
        {
            var server = await dbContext.AuthorizedServers.FindAsync(id);
            if (server == null)
                return NotFound();

            server.IsActive = false;  // Soft delete
            await dbContext.SaveChangesAsync();
            return NoContent();
        }

        private async Task<bool> AuthorizedServerExists(long id)
        {
            return await dbContext.AuthorizedServers.AnyAsync(e => e.ServerID == id);
        }
    }
}