using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AdcsCertificateApi;
using System;
using System.Threading.Tasks;
using System.Collections.Generic;
using Serilog;

namespace AdcsCertificateApi.Controllers
{
    [Authorize(Policy = "KerberosOnly")] // Requires SPN for the app pool gMSA account and membership in FRS98470\grp98470c47-sys-l-A47-ManangeAPI
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
            Log.Information("Fetching all AuthorizedServers");
            var servers = await dbContext.AuthorizedServers.ToListAsync();
            return Ok(servers);
        }

        // GET /api/Manage/AuthorizedServers/{id}
        [HttpGet("AuthorizedServers/{id}")]
        public async Task<ActionResult<AuthorizedServer>> GetAuthorizedServer(long id)
        {
            Log.Information("Fetching AuthorizedServer with ID: {ServerID}", id);
            var server = await dbContext.AuthorizedServers.FindAsync(id);
            if (server == null)
            {
                Log.Warning("AuthorizedServer not found for ID: {ServerID}", id);
                return NotFound();
            }
            return Ok(server);
        }

        // POST /api/Manage/AuthorizedServers
        [HttpPost("AuthorizedServers")]
        public async Task<ActionResult<AuthorizedServerResponseDto>> CreateAuthorizedServer([FromBody] AuthorizedServerDto server)
        {
            Log.Information("Creating AuthorizedServer: AdcsServerAccount={AdcsServerAccount}, ServerGUID={ServerGUID}", server.AdcsServerAccount, server.ServerGUID);

            if (!Guid.TryParse(server.ServerGUID, out _))
            {
                Log.Error("Invalid ServerGUID format: {ServerGUID}", server.ServerGUID);
                return BadRequest("Invalid ServerGUID format. Must be a valid GUID.");
            }

            // Check unique constraint
            if (await dbContext.AuthorizedServers.AnyAsync(s => s.AdcsServerAccount == server.AdcsServerAccount && s.ServerGUID == server.ServerGUID))
            {
                Log.Warning("Combination of AdcsServerAccount {AdcsServerAccount} and ServerGUID {ServerGUID} already exists", server.AdcsServerAccount, server.ServerGUID);
                return Conflict("Combination of AdcsServerAccount and ServerGUID already exists.");
            }

            var newServer = new AuthorizedServer
            {
                AdcsServerAccount = server.AdcsServerAccount,
                AdcsServerName = server.AdcsServerName,
                ServerGUID = server.ServerGUID,
                Description = server.Description,
                IsActive = server.IsActive,
                CreatedAt = DateTime.UtcNow
            };

            dbContext.AuthorizedServers.Add(newServer);
            await dbContext.SaveChangesAsync();

            var response = new AuthorizedServerResponseDto
            {
                ServerID = newServer.ServerID,
                AdcsServerAccount = newServer.AdcsServerAccount,
                AdcsServerName = newServer.AdcsServerName,
                ServerGUID = newServer.ServerGUID,
                Description = newServer.Description,
                IsActive = newServer.IsActive,
                CreatedAt = newServer.CreatedAt
            };

            Log.Information("Successfully created AuthorizedServer with ID: {ServerID}", newServer.ServerID);
            return CreatedAtAction(nameof(GetAuthorizedServer), new { id = newServer.ServerID }, response);
        }

        // PUT /api/Manage/AuthorizedServers/{id}
        [HttpPut("AuthorizedServers/{id}")]
        public async Task<IActionResult> UpdateAuthorizedServer(long id, AuthorizedServer server)
        {
            Log.Information("Updating AuthorizedServer with ID: {ServerID}", id);

            if (id != server.ServerID)
            {
                Log.Error("Mismatched ServerID: {ServerID} does not match request ID: {RequestID}", server.ServerID, id);
                return BadRequest();
            }

            if (!Guid.TryParse(server.ServerGUID, out _))
            {
                Log.Error("Invalid ServerGUID format: {ServerGUID}", server.ServerGUID);
                return BadRequest("Invalid ServerGUID format. Must be a valid GUID.");
            }

            // Check unique constraint (exclude current)
            if (await dbContext.AuthorizedServers.AnyAsync(s => s.AdcsServerAccount == server.AdcsServerAccount && s.ServerGUID == server.ServerGUID && s.ServerID != id))
            {
                Log.Warning("Combination of AdcsServerAccount {AdcsServerAccount} and ServerGUID {ServerGUID} already exists", server.AdcsServerAccount, server.ServerGUID);
                return Conflict("Combination of AdcsServerAccount and ServerGUID already exists.");
            }

            dbContext.Entry(server).State = EntityState.Modified;
            try
            {
                await dbContext.SaveChangesAsync();
                Log.Information("Successfully updated AuthorizedServer with ID: {ServerID}", id);
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!await AuthorizedServerExists(id))
                {
                    Log.Warning("AuthorizedServer not found for ID: {ServerID}", id);
                    return NotFound();
                }
                throw;
            }

            return NoContent();
        }

        // DELETE /api/Manage/AuthorizedServers/{id} (soft delete: set IsActive = false)
        [HttpDelete("AuthorizedServers/{id}")]
        public async Task<IActionResult> DeleteAuthorizedServer(long id)
        {
            Log.Information("Soft deleting AuthorizedServer with ID: {ServerID}", id);
            var server = await dbContext.AuthorizedServers.FindAsync(id);
            if (server == null)
            {
                Log.Warning("AuthorizedServer not found for ID: {ServerID}", id);
                return NotFound();
            }

            server.IsActive = false; // Soft delete
            await dbContext.SaveChangesAsync();
            Log.Information("Successfully soft deleted AuthorizedServer with ID: {ServerID}", id);
            return NoContent();
        }

        private async Task<bool> AuthorizedServerExists(long id)
        {
            return await dbContext.AuthorizedServers.AnyAsync(e => e.ServerID == id);
        }
    }
}