using AdcsCertificateApi;
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
        sqlOptions => sqlOptions.EnableRetryOnFailure(  // Retry up to 5 times on transients
            maxRetryCount: 5,
            maxRetryDelay: TimeSpan.FromSeconds(10),
            errorNumbersToAdd: null
        )
    )
    .EnableSensitiveDataLogging()  // Temp: Logs connection details; remove in prod
    .EnableDetailedErrors()  // More exception info
);

builder.Services.AddControllers();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}

app.UseHttpsRedirection();
app.UseRouting();
app.UseMiddleware<AdcsCertificateApi.MtlsAuthMiddleware>();
app.UseAuthorization();
app.MapControllers();

app.Run();