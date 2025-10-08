using AdcsCertificateApi;
using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using Serilog.Events;
using System;
using System.Security.Principal;
using System.Threading.Tasks;

var builder = WebApplication.CreateBuilder(args);

// Configureer Serilog met extra logging voor authenticatie
builder.Host.UseSerilog((context, configuration) =>
{
    configuration
        .MinimumLevel.Verbose()
        .MinimumLevel.Override("Microsoft", LogEventLevel.Verbose)
        .MinimumLevel.Override("Microsoft.AspNetCore.Authentication", LogEventLevel.Verbose)
        .MinimumLevel.Override("AdcsCertificateApi", LogEventLevel.Verbose)
        .WriteTo.Console(
            outputTemplate: "[{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz}] [{Level:u3}] {Message:lj}{NewLine}{Exception}",
            restrictedToMinimumLevel: LogEventLevel.Verbose)
        .WriteTo.File(
            path: "C:\\Logs\\AdcsCertificateApi.log",
            rollingInterval: RollingInterval.Day,
            restrictedToMinimumLevel: LogEventLevel.Verbose,
            fileSizeLimitBytes: 50_000_000,
            rollOnFileSizeLimit: true,
            buffered: false,
            flushToDiskInterval: TimeSpan.FromSeconds(1),
            outputTemplate: "[{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz}] [{Level:u3}] {Message:lj}{NewLine}{Exception}");
});

builder.Services.AddDbContext<AuthDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("AuthDb"),
        sqlOptions => sqlOptions.EnableRetryOnFailure(
            maxRetryCount: 5,
            maxRetryDelay: TimeSpan.FromSeconds(10),
            errorNumbersToAdd: null
        )
    )
    .EnableSensitiveDataLogging() // Temp: Logs connection details; remove in prod
    .EnableDetailedErrors() // More exception info
);

// Add authentication with Negotiate for Kerberos
builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = NegotiateDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = NegotiateDefaults.AuthenticationScheme;
}).AddNegotiate();

// Add controllers
builder.Services.AddControllers().AddJsonOptions(options =>
{
    options.JsonSerializerOptions.PropertyNameCaseInsensitive = true; // Enable case-insensitive deserialization
});

// Add authorization with group membership requirement
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("KerberosOnly", policy =>
        policy
            .RequireAuthenticatedUser()
            .AddAuthenticationSchemes(NegotiateDefaults.AuthenticationScheme)
            .AddRequirements(new NestedGroupRequirement(
                groupName: builder.Configuration["ActiveDirectory:GroupName"] ?? "FRS98470\\grp98470c47-sys-l-A47-ManangeAPI"
            )));
});

// Add custom authorization handler
builder.Services.AddSingleton<IAuthorizationHandler, NestedGroupAuthorizationHandler>();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}

app.UseHttpsRedirection();
app.UseRouting();

// Enable authentication and authorization middleware
app.UseAuthentication();
app.UseAuthorization();

// Custom middleware to apply mTLS only to non-Manage endpoints
app.UseWhen(context => !context.Request.Path.StartsWithSegments("/api/Manage"), appBuilder =>
{
    appBuilder.UseMiddleware<AdcsCertificateApi.Middleware.MtlsAuthMiddleware>();
});

app.MapControllers();

app.Run();

// Custom authorization requirement for nested groups
public class NestedGroupRequirement : IAuthorizationRequirement
{
    public string GroupName { get; }

    public NestedGroupRequirement(string groupName)
    {
        GroupName = groupName;
    }
}

public class NestedGroupAuthorizationHandler : AuthorizationHandler<NestedGroupRequirement>
{
    protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, NestedGroupRequirement requirement)
    {
        var user = context.User;
        if (user.Identity?.IsAuthenticated != true)
        {
            Log.Warning("User is not authenticated for KerberosOnly policy");
            return Task.CompletedTask;
        }

        try
        {
            // Get current user from Kerberos context
            var currentUser = user as WindowsPrincipal;
            if (currentUser == null)
            {
                Log.Warning("No valid Windows identity found for user");
                return Task.CompletedTask;
            }

            Log.Information("Current user: {UserName}", currentUser.Identity.Name);

            // Check group membership using WindowsPrincipal.IsInRole
            bool isMember = currentUser.IsInRole(requirement.GroupName);
            if (isMember)
            {
                Log.Information("User {UserName} is a member of {GroupName}", currentUser.Identity.Name, requirement.GroupName);
                context.Succeed(requirement);
            }
            else
            {
                Log.Warning("User {UserName} is not a member of {GroupName}", currentUser.Identity.Name, requirement.GroupName);
            }

            return Task.CompletedTask;
        }
        catch (Exception ex)
        {
            Log.Error("Error checking group membership for {UserName}: {Error}", user.Identity.Name, ex);
            return Task.CompletedTask;
        }
    }
}