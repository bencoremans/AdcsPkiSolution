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
    [Authorize(Policy = "KerberosOnly")]
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
            // Check unique constraint for AdcsServerAccount
            if (await dbContext.AuthorizedServers.AnyAsync(s => s.AdcsServerAccount == server.AdcsServerAccount))
            {
                Log.Warning("AdcsServerAccount {AdcsServerAccount} already exists", server.AdcsServerAccount);
                return Conflict("AdcsServerAccount already exists.");
            }
            // Check unique constraint for AdcsServerName
            if (await dbContext.AuthorizedServers.AnyAsync(s => s.AdcsServerName == server.AdcsServerName))
            {
                Log.Warning("AdcsServerName {AdcsServerName} already exists", server.AdcsServerName);
                return Conflict("AdcsServerName already exists.");
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
            try
            {
                await dbContext.SaveChangesAsync();
                Log.Information("Successfully created AuthorizedServer with ID: {ServerID}", newServer.ServerID);
            }
            catch (DbUpdateException ex) when (ex.InnerException is Microsoft.Data.SqlClient.SqlException sqlEx && sqlEx.Number == 2627)
            {
                Log.Error("Unique key violation for AdcsServerAccount {AdcsServerAccount} or AdcsServerName {AdcsServerName}: {Error}", server.AdcsServerAccount, server.AdcsServerName, ex);
                return Conflict("AdcsServerAccount or AdcsServerName already exists.");
            }
            catch (Exception ex)
            {
                Log.Error("Error creating AuthorizedServer: {Error}", ex);
                return StatusCode(500, $"Error creating AuthorizedServer: {ex.Message}");
            }
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
            return CreatedAtAction(nameof(GetAuthorizedServer), new { id = newServer.ServerID }, response);
        }

        // PUT /api/Manage/AuthorizedServers/{id}
        [HttpPut("AuthorizedServers/{id}")]
        public async Task<IActionResult> UpdateAuthorizedServer(long id, AuthorizedServerDto server)
        {
            Log.Information("Updating AuthorizedServer with ID: {ServerID}", id);
            if (!Guid.TryParse(server.ServerGUID, out _))
            {
                Log.Error("Invalid ServerGUID format: {ServerGUID}", server.ServerGUID);
                return BadRequest("Invalid ServerGUID format. Must be a valid GUID.");
            }
            // Check unique constraint for AdcsServerAccount (exclude current)
            if (await dbContext.AuthorizedServers.AnyAsync(s => s.AdcsServerAccount == server.AdcsServerAccount && s.ServerID != id))
            {
                Log.Warning("AdcsServerAccount {AdcsServerAccount} already exists for another server", server.AdcsServerAccount);
                return Conflict("AdcsServerAccount already exists.");
            }
            // Check unique constraint for AdcsServerName (exclude current)
            if (await dbContext.AuthorizedServers.AnyAsync(s => s.AdcsServerName == server.AdcsServerName && s.ServerID != id))
            {
                Log.Warning("AdcsServerName {AdcsServerName} already exists for another server", server.AdcsServerName);
                return Conflict("AdcsServerName already exists.");
            }
            // Fetch existing server to preserve CreatedAt
            var existingServer = await dbContext.AuthorizedServers.FindAsync(id);
            if (existingServer == null)
            {
                Log.Warning("AuthorizedServer not found for ID: {ServerID}", id);
                return NotFound();
            }
            // Update fields, preserving CreatedAt
            existingServer.AdcsServerAccount = server.AdcsServerAccount;
            existingServer.AdcsServerName = server.AdcsServerName;
            existingServer.ServerGUID = server.ServerGUID;
            existingServer.Description = server.Description;
            existingServer.IsActive = server.IsActive;
            // Expliciet aangeven welke eigenschappen gewijzigd zijn
            dbContext.Entry(existingServer).Property(x => x.AdcsServerAccount).IsModified = true;
            dbContext.Entry(existingServer).Property(x => x.AdcsServerName).IsModified = true;
            dbContext.Entry(existingServer).Property(x => x.ServerGUID).IsModified = true;
            dbContext.Entry(existingServer).Property(x => x.Description).IsModified = true;
            dbContext.Entry(existingServer).Property(x => x.IsActive).IsModified = true;
            // CreatedAt wordt expliciet niet gemarkeerd als gewijzigd
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
            catch (DbUpdateException ex) when (ex.InnerException is Microsoft.Data.SqlClient.SqlException sqlEx && sqlEx.Number == 2627)
            {
                Log.Error("Unique key violation for AdcsServerAccount {AdcsServerAccount} or AdcsServerName {AdcsServerName}: {Error}", server.AdcsServerAccount, server.AdcsServerName, ex);
                return Conflict("AdcsServerAccount or AdcsServerName already exists.");
            }
            catch (Exception ex)
            {
                Log.Error("Error updating AuthorizedServer with ID: {ServerID}: {Error}", id, ex);
                return StatusCode(500, $"Error updating AuthorizedServer: {ex.Message}");
            }
            return NoContent();
        }
        // PUT /api/Manage/AuthorizedServers/{id}/active
        [HttpPut("AuthorizedServers/{id}/active")]
        public async Task<IActionResult> UpdateAuthorizedServerActive(long id, [FromBody] bool isActive)
        {
            Log.Information("Updating IsActive for AuthorizedServer with ID: {ServerID} to {IsActive}", id, isActive);

            // Fetch existing server
            var existingServer = await dbContext.AuthorizedServers.FindAsync(id);
            if (existingServer == null)
            {
                Log.Warning("AuthorizedServer not found for ID: {ServerID}", id);
                return NotFound();
            }

            // Update only IsActive
            existingServer.IsActive = isActive;
            dbContext.Entry(existingServer).Property(x => x.IsActive).IsModified = true;

            try
            {
                await dbContext.SaveChangesAsync();
                Log.Information("Successfully updated IsActive for AuthorizedServer with ID: {ServerID}", id);
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
            catch (Exception ex)
            {
                Log.Error("Error updating IsActive for AuthorizedServer with ID: {ServerID}: {Error}", id, ex);
                return StatusCode(500, $"Error updating IsActive for AuthorizedServer: {ex.Message}");
            }

            return NoContent();
        }

        // DELETE /api/Manage/AuthorizedServers/{id}
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