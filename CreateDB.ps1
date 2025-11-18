# Delete the old test table and create the new ADUserLogon table
 
$serverName = "TO COMPLETE"
$databaseName = "TO COMPLETE"
$databaseUser = "TO COMPLETE"
$databasePassword = "TO COMPLETE"

$connectionString = "Server=$serverName;Database=$databaseName;User Id=$databaseUser;Password=$databasePassword;TrustServerCertificate=True;Connection Timeout=30;"
 
try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $connection.Open()
   
    Write-Host "Database connection successful" -ForegroundColor Green
   
    # Delete the old test table if it exists
    Write-Host
    Write-Host "=== Deleting old test table ===" -ForegroundColor Cyan
   
    $dropTestTableCommand = New-Object System.Data.SqlClient.SqlCommand(@"
        IF EXISTS (SELECT * FROM sys.tables WHERE name = 'AD_Audit_Test')
        BEGIN
            DROP TABLE AD_Audit_Test
            PRINT 'Table AD_Audit_Test deleted'
        END
        ELSE
        BEGIN
            PRINT 'Table AD_Audit_Test does not exist'
        END
"@, $connection)
   
    $dropTestTableCommand.ExecuteNonQuery()
    Write-Host "Old table cleaned up" -ForegroundColor Green
   
    # Create the new ADUserLogon table
    Write-Host
    Write-Host "=== Creating ADUserLogon table ===" -ForegroundColor Cyan
   
    $createTableCommand = New-Object System.Data.SqlClient.SqlCommand(@"
        IF EXISTS (SELECT * FROM sys.tables WHERE name = 'ADUserLogon')
        BEGIN
            PRINT 'Table ADUserLogon already exists, deleting...'
            DROP TABLE ADUserLogon
        END
       
        CREATE TABLE ADUserLogon (
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
       
        PRINT 'Table ADUserLogon created successfully'
"@, $connection)
   
    $createTableCommand.ExecuteNonQuery()
    Write-Host "Table ADUserLogon created successfully" -ForegroundColor Green
   
    # Verify the structure of the created table
    Write-Host
    Write-Host "=== ADUserLogon table structure ===" -ForegroundColor Cyan
   
    $checkStructureCommand = New-Object System.Data.SqlClient.SqlCommand(@"
        SELECT
            COLUMN_NAME,
            DATA_TYPE,
            CHARACTER_MAXIMUM_LENGTH,
            IS_NULLABLE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'ADUserLogon'
        ORDER BY ORDINAL_POSITION
"@, $connection)
   
    $reader = $checkStructureCommand.ExecuteReader()
   
    Write-Host "COLUMN_NAME          DATA_TYPE    MAX_LENGTH  NULLABLE" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
   
    while ($reader.Read()) {
        $columnName = $reader['COLUMN_NAME'].ToString().PadRight(20)
        $dataType = $reader['DATA_TYPE'].ToString().PadRight(12)
        $maxLenValue = $reader['CHARACTER_MAXIMUM_LENGTH']
        if ($maxLenValue -eq [DBNull]::Value) {
            $maxLen = "N/A".PadRight(10)
        } else {
            $maxLen = $maxLenValue.ToString().PadRight(10)
        }
        $nullable = $reader['IS_NULLABLE'].ToString()
       
        Write-Host "$columnName $dataType $maxLen $nullable" -ForegroundColor White
    }
    $reader.Close()
   
    Write-Host
    Write-Host "Table ADUserLogon is ready to use!" -ForegroundColor Green
   
    # Test inserting a sample record
    Write-Host
    Write-Host "=== Testing insertion of a sample record ===" -ForegroundColor Cyan
   
    $insertTestCommand = New-Object System.Data.SqlClient.SqlCommand(@"
        INSERT INTO ADUserLogon (SamAccountName, Name, Status, LastLogon, Days, Mail, MailManager, Relance1, Relance2)
        VALUES ('TO COMPLETE', 'TO COMPLETE', 'TO COMPLETE', 'TO COMPLETE', 0, NULL, NULL, 0, 0)
"@, $connection)
   
    $insertResult = $insertTestCommand.ExecuteNonQuery()
    Write-Host "$insertResult record inserted successfully" -ForegroundColor Green
   
    # Verify the insertion
    $selectCommand = New-Object System.Data.SqlClient.SqlCommand("SELECT * FROM ADUserLogon", $connection)
    $selectReader = $selectCommand.ExecuteReader()
   
    Write-Host
    Write-Host "=== Table content ===" -ForegroundColor Cyan
   
    while ($selectReader.Read()) {
        Write-Host "ID: $($selectReader['Id'])" -ForegroundColor White
        Write-Host "SamAccountName: $($selectReader['SamAccountName'])" -ForegroundColor White
        Write-Host "Name: $($selectReader['Name'])" -ForegroundColor White
        Write-Host "Status: $($selectReader['Status'])" -ForegroundColor White
        Write-Host "LastLogon: $($selectReader['LastLogon'])" -ForegroundColor White
        Write-Host "Days: $($selectReader['Days'])" -ForegroundColor White
        Write-Host "Mail: $($selectReader['Mail'])" -ForegroundColor White
        Write-Host "MailManager: $($selectReader['MailManager'])" -ForegroundColor White
        Write-Host "Relance1: $($selectReader['Relance1'])" -ForegroundColor White
        Write-Host "Relance2: $($selectReader['Relance2'])" -ForegroundColor White
        Write-Host "---" -ForegroundColor Gray
    }
    $selectReader.Close()
   
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($connection -and $connection.State -eq 'Open') {
        $connection.Close()
        Write-Host
        Write-Host "Connection closed." -ForegroundColor Gray
    }
}