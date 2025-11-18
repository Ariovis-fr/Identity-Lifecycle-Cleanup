CREATE TABLE ADUserLogon ( -- Stores information from DC
    Id INT IDENTITY(1,1) PRIMARY KEY,        
    SamAccountName VARCHAR(100) NOT NULL,
    Name VARCHAR(200) NOT NULL,
    Status VARCHAR(500) NULL,
    LastLogon DATETIME NULL,
    Days INT NULL,
    Mail VARCHAR(100) NULL,
    MailManager VARCHAR(100) NULL,
    Relance1 BIT NULL,
    Relance2 BIT NULL
);


CREATE TABLE EntraIDUserSignIn ( -- Stores information from Entra ID
    Id INT IDENTITY(1,1) PRIMARY KEY,
    DisplayName NVARCHAR(255),
    UserPrincipalName NVARCHAR(255),
    LastSignIn DATETIME
);


