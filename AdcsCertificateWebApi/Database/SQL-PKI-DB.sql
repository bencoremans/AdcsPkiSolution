-- SQL Script to create and configure a database from scratch
-- Version: 3.0 - Fixed gMSA permission context issue with explicit database references, preserves original table structure

-- Declare variables for database name and gMSA account
DECLARE @DatabaseName NVARCHAR(128) = 'AdcsCertificateDbV2'; -- Replace with your database name
DECLARE @gMSAAccount NVARCHAR(512) = 'FRS98470\gmsa_pki20api$'; -- Replace with your gMSA account
DECLARE @ErrorMessage NVARCHAR(4000);
DECLARE @CurrentDatabase NVARCHAR(128);

-- Check if database exists, close connections, and drop it
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName)
    BEGIN
        -- Set database to single-user mode to close existing connections
        EXEC('ALTER DATABASE [' + @DatabaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE');
        PRINT 'Set ' + @DatabaseName + ' to single-user mode to close connections.';
        
        -- Drop the database
        EXEC('DROP DATABASE [' + @DatabaseName + ']');
        PRINT 'Database ' + @DatabaseName + ' dropped successfully.';
    END
END TRY
BEGIN CATCH
    SET @ErrorMessage = ERROR_MESSAGE();
    RAISERROR ('Error dropping database %s: %s', 16, 1, @DatabaseName, @ErrorMessage);
    RETURN;
END CATCH

-- Create new database
BEGIN TRY
    EXEC('CREATE DATABASE [' + @DatabaseName + ']');
    PRINT 'Database ' + @DatabaseName + ' created successfully.';
END TRY
BEGIN CATCH
    SET @ErrorMessage = ERROR_MESSAGE();
    RAISERROR ('Error creating database %s: %s', 16, 1, @DatabaseName, @ErrorMessage);
    RETURN;
END CATCH

-- Verify database exists before proceeding
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName)
BEGIN
    RAISERROR ('Database %s was not created successfully.', 16, 1, @DatabaseName);
    RETURN;
END

-- Create tables with explicit database references
BEGIN TRY
    -- Create table for CA information
    EXEC('CREATE TABLE [' + @DatabaseName + '].dbo.CAs (
        AdcsServerName VARCHAR(50) PRIMARY KEY,
        IssuerName NVARCHAR(512) NOT NULL,
        Description NVARCHAR(200) NULL,
        CONSTRAINT UQ_IssuerName UNIQUE (IssuerName)
    )');
    PRINT 'Table CAs created successfully in ' + @DatabaseName + '.';

    -- Create table for certificate templates
    EXEC('CREATE TABLE [' + @DatabaseName + '].dbo.CertificateTemplates (
        TemplateID BIGINT IDENTITY(1,1) PRIMARY KEY,
        TemplateName NVARCHAR(255) NOT NULL,
        TemplateOID NVARCHAR(255) NOT NULL,
        CONSTRAINT UQ_TemplateOID UNIQUE (TemplateOID)
    )');
    PRINT 'Table CertificateTemplates created successfully in ' + @DatabaseName + '.';

    -- Create table for authorized servers
    EXEC('CREATE TABLE [' + @DatabaseName + '].dbo.AuthorizedServers (
        ServerID BIGINT IDENTITY(1,1) PRIMARY KEY,
        RequesterName NVARCHAR(512) NOT NULL,
        Description NVARCHAR(200) NULL,
        CreatedAt DATETIME DEFAULT GETDATE(),
        IsActive BIT DEFAULT 1,
        CONSTRAINT UQ_RequesterName UNIQUE (RequesterName)
    );
    CREATE INDEX IDX_AuthorizedServers_Active ON [' + @DatabaseName + '].dbo.AuthorizedServers (IsActive)');
    PRINT 'Table AuthorizedServers created successfully in ' + @DatabaseName + '.';

    -- Create table for certificate logs
    EXEC('CREATE TABLE [' + @DatabaseName + '].dbo.CertificateLogs (
        CertificateID BIGINT IDENTITY(1,1) PRIMARY KEY,
        AdcsServerName VARCHAR(50) NOT NULL,
        SerialNumber VARCHAR(128) NOT NULL,
        Request_RequestID BIGINT NOT NULL,
        Disposition BIGINT NOT NULL DEFAULT 9,
        SubmittedWhen DATETIME NOT NULL DEFAULT GETDATE(),
        ResolvedWhen DATETIME NULL,
        RevokedWhen DATETIME NULL,
        RevokedEffectiveWhen DATETIME NULL,
        RevokedReason BIGINT NULL,
        RequesterName NVARCHAR(512) NULL,
        CallerName NVARCHAR(512) NULL,
        NotBefore DATETIME NOT NULL,
        NotAfter DATETIME NOT NULL,
        SubjectKeyIdentifier VARCHAR(128) NULL,
        Thumbprint VARCHAR(128) NULL,
        TemplateID BIGINT NOT NULL,
        RequestType BIGINT NULL,
        RequestFlags BIGINT NULL,
        StatusCode BIGINT NULL,
        DispositionMessage NVARCHAR(4000) NULL,
        SignerPolicies NVARCHAR(4000) NULL,
        SignerApplicationPolicies NVARCHAR(4000) NULL,
        Officer BIGINT NULL,
        KeyRecoveryHashes NVARCHAR(4000) NULL,
        EnrollmentFlags BIGINT NULL,
        GeneralFlags BIGINT NULL,
        PrivateKeyFlags BIGINT NULL,
        PublishExpiredCertInCRL BIGINT NULL,
        PublicKeyLength VARCHAR(50) NULL,
        PublicKeyAlgorithm NVARCHAR(254) NULL,
        CONSTRAINT FK_CertificateLogs_CAs FOREIGN KEY (AdcsServerName) REFERENCES [' + @DatabaseName + '].dbo.CAs (AdcsServerName),
        CONSTRAINT FK_CertificateLogs_Templates FOREIGN KEY (TemplateID) REFERENCES [' + @DatabaseName + '].dbo.CertificateTemplates (TemplateID),
        CONSTRAINT UQ_SerialNumber_AdcsServerName UNIQUE (SerialNumber, AdcsServerName),
        CONSTRAINT UQ_RequestID_AdcsServerName UNIQUE (Request_RequestID, AdcsServerName),
        CONSTRAINT CK_Disposition CHECK (Disposition IN (8, 9, 12, 15, 16, 17, 20, 21, 30, 31))
    );
    CREATE INDEX IDX_AdcsServerName ON [' + @DatabaseName + '].dbo.CertificateLogs (AdcsServerName);
    CREATE INDEX IDX_NotAfter ON [' + @DatabaseName + '].dbo.CertificateLogs (NotAfter);
    CREATE INDEX IDX_SubmittedWhen ON [' + @DatabaseName + '].dbo.CertificateLogs (SubmittedWhen);
    CREATE INDEX IDX_TemplateID ON [' + @DatabaseName + '].dbo.CertificateLogs (TemplateID);
    CREATE INDEX IDX_RevokedWhen ON [' + @DatabaseName + '].dbo.CertificateLogs (RevokedWhen)');
    PRINT 'Table CertificateLogs created successfully in ' + @DatabaseName + '.';

    -- Create table for subject attributes
    EXEC('CREATE TABLE [' + @DatabaseName + '].dbo.SubjectAttributes (
        AttributeID BIGINT IDENTITY(1,1) PRIMARY KEY,
        CertificateID BIGINT NOT NULL,
        AttributeType NVARCHAR(50) NOT NULL,
        AttributeValue NVARCHAR(1024) NOT NULL,
        AttributeValueHash BINARY(32) NULL,
        CONSTRAINT FK_SubjectAttributes_CertificateLogs FOREIGN KEY (CertificateID) REFERENCES [' + @DatabaseName + '].dbo.CertificateLogs (CertificateID),
        CONSTRAINT UQ_Attribute_Unique UNIQUE (CertificateID, AttributeType, AttributeValueHash)
    );
    CREATE INDEX IDX_AttributeType ON [' + @DatabaseName + '].dbo.SubjectAttributes (AttributeType)');
    PRINT 'Table SubjectAttributes created successfully in ' + @DatabaseName + '.';

    -- Create table for binary data
    EXEC('CREATE TABLE [' + @DatabaseName + '].dbo.CertificateBinaries (
        RequestID BIGINT IDENTITY(1,1) PRIMARY KEY,
        CertificateID BIGINT NOT NULL,
        RawRequest VARBINARY(MAX) NULL,
        RawArchivedKey VARBINARY(MAX) NULL,
        RawOldCertificate VARBINARY(MAX) NULL,
        RawName VARBINARY(MAX) NULL,
        RawCertificate VARBINARY(MAX) NULL,
        RawPublicKey VARBINARY(MAX) NULL,
        RawPublicKeyAlgorithmParameters VARBINARY(MAX) NULL,
        AttestationChallenge VARBINARY(MAX) NULL,
        CONSTRAINT FK_CertificateBinaries_CertificateLogs FOREIGN KEY (CertificateID) REFERENCES [' + @DatabaseName + '].dbo.CertificateLogs (CertificateID)
    );
    CREATE INDEX IDX_Binaries_CertificateID ON [' + @DatabaseName + '].dbo.CertificateBinaries (CertificateID)');
    PRINT 'Table CertificateBinaries created successfully in ' + @DatabaseName + '.';

    -- Create table for SANs
    EXEC('CREATE TABLE [' + @DatabaseName + '].dbo.CertificateSANS (
        SANSID BIGINT IDENTITY(1,1) PRIMARY KEY,
        CertificateID BIGINT NOT NULL,
        SANSValue NVARCHAR(255) NOT NULL,
        SANSType VARCHAR(50) NOT NULL,
        CONSTRAINT FK_CertificateSANS_CertificateLogs FOREIGN KEY (CertificateID) REFERENCES [' + @DatabaseName + '].dbo.CertificateLogs (CertificateID),
        CONSTRAINT UQ_SANS_Unique UNIQUE (CertificateID, SANSValue, SANSType)
    );
    CREATE INDEX IDX_SANS_CertificateID ON [' + @DatabaseName + '].dbo.CertificateSANS (CertificateID);
    CREATE INDEX IDX_SANSValue ON [' + @DatabaseName + '].dbo.CertificateSANS (SANSValue);
    CREATE INDEX IDX_SANSType ON [' + @DatabaseName + '].dbo.CertificateSANS (SANSType)');
    PRINT 'Table CertificateSANS created successfully in ' + @DatabaseName + '.';
END TRY
BEGIN CATCH
    SET @ErrorMessage = ERROR_MESSAGE();
    RAISERROR ('Error creating tables in database %s: %s', 16, 1, @DatabaseName, @ErrorMessage);
    RETURN;
END CATCH

-- Grant permissions to gMSA account with explicit database context
BEGIN TRY
    -- Create login if it doesn't exist
    IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = @gMSAAccount)
    BEGIN
        EXEC('CREATE LOGIN [' + @gMSAAccount + '] FROM WINDOWS WITH DEFAULT_DATABASE = [' + @DatabaseName + ']');
        PRINT 'Login for ' + @gMSAAccount + ' created successfully.';
    END
    ELSE
    BEGIN
        PRINT 'Login for ' + @gMSAAccount + ' already exists.';
    END

    -- Create user and grant permissions in the correct database
    EXEC('
        USE [' + @DatabaseName + '];
        IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = ''' + @gMSAAccount + ''')
        BEGIN
            CREATE USER [' + @gMSAAccount + '] FOR LOGIN [' + @gMSAAccount + '];
        END
        ALTER ROLE db_datareader ADD MEMBER [' + @gMSAAccount + '];
        ALTER ROLE db_datawriter ADD MEMBER [' + @gMSAAccount + '];
        GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO [' + @gMSAAccount + '];
    ');
    PRINT 'User created and permissions (db_datareader, db_datawriter, SELECT, INSERT, UPDATE, DELETE) granted to ' + @gMSAAccount + ' in ' + @DatabaseName + '.';
END TRY
BEGIN CATCH
    SET @ErrorMessage = ERROR_MESSAGE();
    RAISERROR ('Error granting permissions to %s in database %s: %s', 16, 1, @gMSAAccount, @DatabaseName, @ErrorMessage);
    RETURN;
END CATCH