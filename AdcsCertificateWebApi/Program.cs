using AdcsCertificateApi;
using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.AspNetCore.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using Serilog.Events;

var builder = WebApplication.CreateBuilder(args);

// Configureer Serilog
builder.Host.UseSerilog((context, configuration) =>
{
    configuration
        .MinimumLevel.Verbose()
        .MinimumLevel.Override("Microsoft", LogEventLevel.Verbose)
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

// Add authorization
builder.Services.AddAuthorization(options =>
{
    // Define a policy for ManageController to require Kerberos
    options.AddPolicy("KerberosOnly", policy =>
        policy
            .RequireAuthenticatedUser()
            .AddAuthenticationSchemes(NegotiateDefaults.AuthenticationScheme));
});

builder.Services.AddControllers().AddJsonOptions(options =>
{
    options.JsonSerializerOptions.PropertyNameCaseInsensitive = true; // Enable case-insensitive deserialization
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}

app.UseHttpsRedirection();
app.UseRouting();

// Enable authentication middleware
app.UseAuthentication();
app.UseAuthorization();

// Custom middleware to apply mTLS only to non-Manage endpoints
app.UseWhen(context => !context.Request.Path.StartsWithSegments("/api/Manage"), appBuilder =>
{
    appBuilder.UseMiddleware<AdcsCertificateApi.Middleware.MtlsAuthMiddleware>();
});

app.MapControllers();

app.Run();