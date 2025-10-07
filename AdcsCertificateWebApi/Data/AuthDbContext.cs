using Microsoft.EntityFrameworkCore;

namespace AdcsCertificateApi
{
    public class CertificateLog
    {
        public long CertificateID { get; set; }  // NOT NULL, PK
        public string AdcsServerName { get; set; }  // NOT NULL
        public string SerialNumber { get; set; }  // NOT NULL
        public long Request_RequestID { get; set; }  // NOT NULL
        public long Disposition { get; set; }  // NOT NULL
        public DateTime SubmittedWhen { get; set; }  // NOT NULL
        public DateTime? ResolvedWhen { get; set; }  // NULL
        public DateTime? RevokedWhen { get; set; }  // NULL
        public DateTime? RevokedEffectiveWhen { get; set; }  // NULL
        public long? RevokedReason { get; set; }  // NULL
        public string? RequesterName { get; set; }  // NULL
        public string? CallerName { get; set; }  // NULL
        public DateTime NotBefore { get; set; }  // NOT NULL
        public DateTime NotAfter { get; set; }  // NOT NULL
        public string? SubjectKeyIdentifier { get; set; }  // NULL
        public string Thumbprint { get; set; }  // NOT NULL
        public long TemplateID { get; set; }  // NOT NULL
        public long? RequestType { get; set; }  // NULL
        public long? RequestFlags { get; set; }  // NULL
        public long? StatusCode { get; set; }  // NULL
        public string? DispositionMessage { get; set; }  // NOT NULL in DB, temporarily nullable
        public string? SignerPolicies { get; set; }  // NOT NULL in DB, temporarily nullable
        public string? SignerApplicationPolicies { get; set; }  // NOT NULL in DB, temporarily nullable
        public long? Officer { get; set; }  // NULL
        public string? KeyRecoveryHashes { get; set; }  // NOT NULL in DB, temporarily nullable
        public long? EnrollmentFlags { get; set; }  // NULL
        public long? GeneralFlags { get; set; }  // NULL
        public long? PrivateKeyFlags { get; set; }  // NULL
        public long? PublishExpiredCertInCRL { get; set; }  // NULL
        public string? PublicKeyLength { get; set; }  // NULL
        public string? PublicKeyAlgorithm { get; set; }  // NULL
    }

    public class CertificateSan
    {
        public long SANSID { get; set; }
        public long CertificateID { get; set; }
        public string SANSValue { get; set; }
        public string SANSType { get; set; }
    }

    public class CA
    {
        public string AdcsServerName { get; set; }
        public string IssuerName { get; set; }
        public string? Description { get; set; }
    }

    public class CertificateTemplate
    {
        public long TemplateID { get; set; }
        public string TemplateName { get; set; }
        public string TemplateOID { get; set; }
    }

    public class SubjectAttribute
    {
        public long AttributeID { get; set; }
        public long CertificateID { get; set; }
        public string AttributeType { get; set; }
        public string AttributeValue { get; set; }
        public byte[] AttributeValueHash { get; set; }
    }

    public class AuthorizedServer
    {
        public long ServerID { get; set; }
        public string AdcsServerAccount { get; set; } 
        public string AdcsServerName { get; set; }
        public string ServerGUID { get; set; }  // New field, NOT NULL
        public string? Description { get; set; }
        public DateTime CreatedAt { get; set; }
        public bool IsActive { get; set; }
    }

    public class AuthDbContext : DbContext
    {
        public AuthDbContext(DbContextOptions<AuthDbContext> options) : base(options)
        {
        }

        public DbSet<CertificateLog> CertificateLogs { get; set; }
        public DbSet<CertificateSan> CertificateSANS { get; set; }
        public DbSet<CA> CAs { get; set; }
        public DbSet<CertificateTemplate> CertificateTemplates { get; set; }
        public DbSet<SubjectAttribute> SubjectAttributes { get; set; }
        public DbSet<AuthorizedServer> AuthorizedServers { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<AuthorizedServer>()
                .HasKey(a => a.ServerID);

            // Optioneel: Configureer andere constraints
            modelBuilder.Entity<AuthorizedServer>()
                .HasIndex(a => a.AdcsServerName)
                .IsUnique();

            modelBuilder.Entity<CertificateLog>()
                .HasKey(c => c.CertificateID);

            modelBuilder.Entity<CA>()
                .HasKey(c => c.AdcsServerName);

            modelBuilder.Entity<CertificateTemplate>()
                .HasKey(t => t.TemplateID);

            modelBuilder.Entity<SubjectAttribute>()
                .HasKey(s => s.AttributeID);

            modelBuilder.Entity<CertificateSan>()
                .HasKey(s => s.SANSID);
        }
    }
}