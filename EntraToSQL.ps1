# Get Inactive Users from EntraID - Set to 75 days

Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All"
$days = 75
$cutoffDate = (Get-Date).AddDays(-$days)


$users = Get-MgUser -All -Property "displayName,userPrincipalName,signInActivity" | 
    Where-Object { $_.SignInActivity.LastSignInDateTime -lt $cutoffDate }

    $users | Select-Object displayName, userPrincipalName, @{Name="LastSignIn"; Expression={$_.SignInActivity.LastSignInDateTime}}


$SqlServer = "TO COMPLETE"       
$Database = "TO COMPLETE"    
$Table = "TO COMPLETE"       
$SqlUser = "TO COMPLETE"
$SqlPassword = "TO COMPLETE"

$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server=$SqlServer;Database=$Database;User Id=$SqlUser;Password=$SqlPassword;TrustServerCertificate=True;Connection Timeout=30;"
$SqlConnection.Open()


$SqlCommand = $SqlConnection.CreateCommand()

$SqlCommand.CommandText = @"
INSERT INTO $Table (DisplayName, UserPrincipalName, LastSignIn)
VALUES (@DisplayName, @UserPrincipalName, @LastSignIn)
"@

$SqlCommand.Parameters.Add("@DisplayName", [System.Data.SqlDbType]::NVarChar, 255) | Out-Null
$SqlCommand.Parameters.Add("@UserPrincipalName", [System.Data.SqlDbType]::NVarChar, 255) | Out-Null
$SqlCommand.Parameters.Add("@LastSignIn", [System.Data.SqlDbType]::DateTime) | Out-Null

foreach ($user in $users) {
    $SqlCommand.Parameters["@DisplayName"].Value = $user.DisplayName
    $SqlCommand.Parameters["@UserPrincipalName"].Value = $user.UserPrincipalName
    $SqlCommand.Parameters["@LastSignIn"].Value = $user.SignInActivity.LastSignInDateTime

    $SqlCommand.ExecuteNonQuery() | Out-Null
}

$SqlConnection.Close()

Write-Host "Data insertion successful"