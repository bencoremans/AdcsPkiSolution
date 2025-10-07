using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace AdcsCertificateApi.Middleware
{
    public class MtlsAuthMiddleware
    {
        private readonly RequestDelegate _next;

        public MtlsAuthMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context, AuthDbContext dbContext)
        {
            // Step 1: ServerGUID and AdcsServerAccount validation (only for CertificateData endpoint)
            var path = context.Request.Path.Value?.ToLower();
            if (path == "/api/certificatedata")
            {
                // Extract ServerGUID from header
                if (!context.Request.Headers.TryGetValue("X-ADCS-Server-GUID", out var serverGuidHeader) || serverGuidHeader.Count == 0)
                {
                    context.Response.StatusCode = 403;
                    await context.Response.WriteAsync("X-ADCS-Server-GUID header is required.");
                    return;
                }

                string serverGuid = serverGuidHeader[0];
                if (!Guid.TryParse(serverGuid, out _))
                {
                    context.Response.StatusCode = 403;
                    await context.Response.WriteAsync("Invalid ServerGUID format. Must be a valid GUID.");
                    return;
                }

                // Extract AdcsServerName from JSON body
                string? adcsServerName = null;
                try
                {
                    // Enable buffering to read body multiple times
                    context.Request.EnableBuffering();
                    using var reader = new StreamReader(
                        context.Request.Body,
                        encoding: Encoding.UTF8,
                        detectEncodingFromByteOrderMarks: false,
                        bufferSize: 1024,
                        leaveOpen: true);
                    var body = await reader.ReadToEndAsync();
                    context.Request.Body.Position = 0; // Reset body for downstream

                    if (string.IsNullOrEmpty(body))
                    {
                        Console.WriteLine("[DEBUG] Request body is empty.");
                        // Replace with Serilog in production: Serilog.Log.Debug("Request body is empty.");
                        context.Response.StatusCode = 400;
                        await context.Response.WriteAsync("Request body is empty.");
                        return;
                    }

                    // Log the raw body for debugging
                    Console.WriteLine($"[DEBUG] Raw request body: {body}");
                    // Replace with Serilog in production: Serilog.Log.Debug("Raw request body: {Body}", body);

                    using var jsonDoc = JsonDocument.Parse(body);
                    if (jsonDoc.RootElement.TryGetProperty("data", out var dataElement))
                    {
                        if (dataElement.TryGetProperty("adcsServerName", out var serverNameElement))
                        {
                            adcsServerName = serverNameElement.GetString();
                            Console.WriteLine($"[DEBUG] Found adcsServerName: {adcsServerName}");
                            // Replace with Serilog in production: Serilog.Log.Debug("Found adcsServerName: {AdcsServerName}", adcsServerName);
                        }
                        else
                        {
                            Console.WriteLine("[DEBUG] adcsServerName not found in data element.");
                            // Replace with Serilog in production: Serilog.Log.Debug("adcsServerName not found in data element.");
                        }
                    }
                    else
                    {
                        Console.WriteLine("[DEBUG] Data element not found in JSON body.");
                        // Replace with Serilog in production: Serilog.Log.Debug("Data element not found in JSON body.");
                    }
                }
                catch (JsonException ex)
                {
                    Console.WriteLine($"[ERROR] Invalid JSON body: {ex.Message}");
                    // Replace with Serilog in production: Serilog.Log.Error("Invalid JSON body: {Error}", ex.Message);
                    context.Response.StatusCode = 400;
                    await context.Response.WriteAsync($"Invalid JSON body: {ex.Message}");
                    return;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[ERROR] Error parsing request body: {ex.Message}");
                    // Replace with Serilog in production: Serilog.Log.Error("Error parsing request body: {Error}", ex.Message);
                    context.Response.StatusCode = 500;
                    await context.Response.WriteAsync($"Error parsing request body: {ex.Message}");
                    return;
                }

                if (string.IsNullOrEmpty(adcsServerName))
                {
                    Console.WriteLine("[DEBUG] AdcsServerName not found in request body.");
                    // Replace with Serilog in production: Serilog.Log.Debug("AdcsServerName not found in request body.");
                    context.Response.StatusCode = 403;
                    await context.Response.WriteAsync("AdcsServerName not found in request body.");
                    return;
                }

                // Check database
                try
                {
                    var authorizedServer = await dbContext.AuthorizedServers
                        .FirstOrDefaultAsync(s => s.AdcsServerAccount == adcsServerName && s.ServerGUID == serverGuid && s.IsActive);
                    if (authorizedServer == null)
                    {
                        Console.WriteLine($"[DEBUG] Unauthorized server: {adcsServerName}/{serverGuid}");
                        // Replace with Serilog in production: Serilog.Log.Debug("Unauthorized server: {AdcsServerAccount}/{ServerGUID}", adcsServerName, serverGuid);
                        context.Response.StatusCode = 403;
                        await context.Response.WriteAsync($"Unauthorized server: {adcsServerName}/{serverGuid}");
                        return;
                    }
                    else
                    {
                        Console.WriteLine($"[DEBUG] Authorized server found: {adcsServerName}/{serverGuid}");
                        // Replace with Serilog in production: Serilog.Log.Debug("Authorized server found: {AdcsServerAccount}/{ServerGUID}", adcsServerName, serverGuid);
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[ERROR] Database query failed: {ex.Message}");
                    // Replace with Serilog in production: Serilog.Log.Error("Database query failed: {Error}", ex.Message);
                    context.Response.StatusCode = 500;
                    await context.Response.WriteAsync($"Database query failed: {ex.Message}");
                    return;
                }
            }

            // Proceed to next middleware
            await _next(context);
        }
    }

    public static class MtlsAuthMiddlewareExtensions
    {
        public static IApplicationBuilder UseMtlsAuth(this IApplicationBuilder builder)
        {
            return builder.UseMiddleware<MtlsAuthMiddleware>();
        }
    }
}