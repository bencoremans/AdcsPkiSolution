using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography.X509Certificates;
using SysadminsLV.PKI.Cryptography.X509Certificates;
using System.Security.Cryptography;

namespace AdcsCertificateApi
{
    public class MtlsAuthMiddleware
    {
        private readonly RequestDelegate next;
        private readonly AuthDbContext dbContext;

        public MtlsAuthMiddleware(RequestDelegate next, AuthDbContext dbContext)
        {
            this.next = next;
            this.dbContext = dbContext;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            // mTLS-authenticatie is uitgeschakeld voor demonstratie
            /*
            var clientCert = context.Connection.ClientCertificate;
            if (clientCert == null)
            {
                context.Response.StatusCode = 403;
                await context.Response.WriteAsync("No client certificate provided");
                return;
            }

            if (!HasOnlyClientAuthEku(clientCert))
            {
                context.Response.StatusCode = 403;
                await context.Response.WriteAsync("Certificate has invalid EKU");
                return;
            }

            var thumbprint = clientCert.Thumbprint.ToUpper();
            var requesterName = GetRequesterNameFromSan(clientCert);
            if (string.IsNullOrEmpty(requesterName))
            {
                context.Response.StatusCode = 403;
                await context.Response.WriteAsync("No valid userPrincipalName in certificate SAN");
                return;
            }

            var isAuthorized = await dbContext.AuthorizedServers
                .AnyAsync(s => s.RequesterName == requesterName && s.IsActive);
            if (!isAuthorized)
            {
                context.Response.StatusCode = 403;
                await context.Response.WriteAsync("Server not authorized");
                return;
            }

            var isValidCert = await dbContext.CertificateLogs
                .AnyAsync(c => c.Thumbprint == thumbprint && 
                               c.RequesterName == requesterName && 
                               c.NotBefore <= DateTime.Now && 
                               c.NotAfter > DateTime.Now && 
                               c.Disposition == 20);
            if (!isValidCert)
            {
                context.Response.StatusCode = 403;
                await context.Response.WriteAsync("Invalid or expired certificate");
                return;
            }
            */

            await next(context);
        }

        private static bool HasOnlyClientAuthEku(X509Certificate2 cert)
        {
            foreach (var ext in cert.Extensions)
            {
                if (ext is X509EnhancedKeyUsageExtension ekuExt)
                {
                    var ekus = ekuExt.EnhancedKeyUsages;
                    if (ekus.Count != 1 || ekus[0].Value != "1.3.6.1.5.5.7.3.2")
                        return false;
                    return true;
                }
            }
            return false;
        }

        private static string GetRequesterNameFromSan(X509Certificate2 cert)
        {
            var sanExtension = cert.Extensions.Cast<X509Extension>()
                .FirstOrDefault(e => e.Oid.Value == "2.5.29.17");
            if (sanExtension != null)
            {
                var asnEncodedData = new AsnEncodedData(sanExtension.Oid, sanExtension.RawData);
                var san = new X509SubjectAlternativeNamesExtension(asnEncodedData, sanExtension.Critical);
                var upn = san.AlternativeNames
                    .FirstOrDefault(alt => alt.Type.ToString().ToLower() == "userprincipalname")?.Value;
                if (!string.IsNullOrEmpty(upn))
                {
                    var parts = upn.Split('@');
                    if (parts.Length == 2)
                        return $"{parts[1].Split('.')[0]}\\{parts[0]}"; // Bijv. FRS98470\S98470A47A8A001$
                }
            }
            return null;
        }
    }
}