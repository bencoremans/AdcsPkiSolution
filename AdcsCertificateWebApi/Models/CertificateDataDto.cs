using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace AdcsCertificateApi
{
    public class CertificateDataDto
    {
        [JsonPropertyName("Data")]
        [Required(ErrorMessage = "Data is verplicht")]
        public CertificateLogDto Data { get; set; }

        [JsonPropertyName("SANS")]
        public List<CertificateSanDto> SANS { get; set; } = new List<CertificateSanDto>();

        [JsonPropertyName("SubjectAttributes")]
        [Required(ErrorMessage = "SubjectAttributes is verplicht")]
        public List<SubjectAttributeDto> SubjectAttributes { get; set; } = new List<SubjectAttributeDto>();
    }

    public class CertificateLogDto
    {
        [Required(ErrorMessage = "CAID is verplicht")]
        [StringLength(50, ErrorMessage = "CAID mag niet langer zijn dan 50 karakters")]
        public string CAID { get; set; }

        [Required(ErrorMessage = "IssuerName is verplicht")]
        [StringLength(512, ErrorMessage = "IssuerName mag niet langer zijn dan 512 karakters")]
        public string IssuerName { get; set; }

        [Required(ErrorMessage = "AdcsServerAccount is verplicht")]
        [StringLength(50, ErrorMessage = "AdcsServerAccount mag niet langer zijn dan 50 karakters")]
        public string AdcsServerAccount { get; set; } // New field

        [Required(ErrorMessage = "SerialNumber is verplicht")]
        [StringLength(128, ErrorMessage = "SerialNumber mag niet langer zijn dan 128 karakters")]
        public string SerialNumber { get; set; }

        [Required(ErrorMessage = "Request_RequestID is verplicht")]
        public long Request_RequestID { get; set; }

        [Required(ErrorMessage = "Disposition is verplicht")]
        [Range(8, 31, ErrorMessage = "Disposition moet een geldige ADCS-waarde zijn (8, 9, 12, 15, 16, 17, 20, 21, 30, 31)")]
        public long Disposition { get; set; }

        [Required(ErrorMessage = "SubmittedWhen is verplicht")]
        public DateTime SubmittedWhen { get; set; }

        public DateTime? ResolvedWhen { get; set; }

        public DateTime? RevokedWhen { get; set; }

        public DateTime? RevokedEffectiveWhen { get; set; }

        public long? RevokedReason { get; set; }

        [StringLength(512, ErrorMessage = "RequesterName mag niet langer zijn dan 512 karakters")]
        public string? RequesterName { get; set; }

        [StringLength(512, ErrorMessage = "CallerName mag niet langer zijn dan 512 karakters")]
        public string? CallerName { get; set; }

        [Required(ErrorMessage = "NotBefore is verplicht")]
        public DateTime NotBefore { get; set; }

        [Required(ErrorMessage = "NotAfter is verplicht")]
        public DateTime NotAfter { get; set; }

        [StringLength(128, ErrorMessage = "SubjectKeyIdentifier mag niet langer zijn dan 128 karakters")]
        public string? SubjectKeyIdentifier { get; set; }

        [Required(ErrorMessage = "Thumbprint is verplicht")]
        [StringLength(128, ErrorMessage = "Thumbprint mag niet langer zijn dan 128 karakters")]
        public string Thumbprint { get; set; }

        [Required(ErrorMessage = "TemplateOID is verplicht")]
        [StringLength(255, ErrorMessage = "TemplateOID mag niet langer zijn dan 255 karakters")]
        public string TemplateOID { get; set; }

        [StringLength(255, ErrorMessage = "TemplateName mag niet langer zijn dan 255 karakters")]
        public string? TemplateName { get; set; }

        public long? RequestType { get; set; }
        public long? RequestFlags { get; set; }
        public long? StatusCode { get; set; }

        [StringLength(4000, ErrorMessage = "DispositionMessage mag niet langer zijn dan 4000 karakters")]
        public string? DispositionMessage { get; set; }

        [StringLength(4000, ErrorMessage = "SignerPolicies mag niet langer zijn dan 4000 karakters")]
        public string? SignerPolicies { get; set; }

        [StringLength(4000, ErrorMessage = "SignerApplicationPolicies mag niet langer zijn dan 4000 karakters")]
        public string? SignerApplicationPolicies { get; set; }

        public long? Officer { get; set; }

        [StringLength(4000, ErrorMessage = "KeyRecoveryHashes mag niet langer zijn dan 4000 karakters")]
        public string? KeyRecoveryHashes { get; set; }

        public long? EnrollmentFlags { get; set; }
        public long? GeneralFlags { get; set; }
        public long? PrivateKeyFlags { get; set; }
        public long? PublishExpiredCertInCRL { get; set; }

        [StringLength(50, ErrorMessage = "PublicKeyLength mag niet langer zijn dan 50 karakters")]
        public string? PublicKeyLength { get; set; }

        [StringLength(254, ErrorMessage = "PublicKeyAlgorithm mag niet langer zijn dan 254 karakters")]
        public string? PublicKeyAlgorithm { get; set; }
    }

    public class CertificateSanDto
    {
        [Required(ErrorMessage = "SANSType is verplicht")]
        [StringLength(50, ErrorMessage = "SANSType mag niet langer zijn dan 50 karakters")]
        public string SANSType { get; set; }

        public string OID { get; set; }

        [Required(ErrorMessage = "Value is verplicht")]
        [StringLength(255, ErrorMessage = "SANSValue mag niet langer zijn dan 255 karakters")]
        public string Value { get; set; }
    }

    public class SubjectAttributeDto
    {
        [Required(ErrorMessage = "AttributeType is verplicht")]
        [StringLength(50, ErrorMessage = "AttributeType mag niet langer zijn dan 50 karakters")]
        public string AttributeType { get; set; }

        [Required(ErrorMessage = "AttributeValue is verplicht")]
        [StringLength(1024, ErrorMessage = "AttributeValue mag niet langer zijn dan 1024 karakters")]
        public string AttributeValue { get; set; }
    }
}