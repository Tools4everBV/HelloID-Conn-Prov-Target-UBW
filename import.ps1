######################################################
# HelloID-Conn-Prov-Target-UBW-Import-Persons
# PowerShell V2
######################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-UBWError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $friendlyMessage = ($errorDetailsObject.notificationMessages | ConvertTo-Json)
            $httpErrorObj.FriendlyMessage = $friendlyMessage
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Verbose "Starting account data import" -Verbose

    Write-Information 'Creating authentication headers'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)")))")
    

    # Creating dummy data, can be removed when creating your own script
    $importedAccounts = [System.Collections.Generic.List[object]]::new()

    # Retrieve all users
    $splatAllUsersRestParams = @{
        Headers = $headers
        Uri     = "$($actionContext.Configuration.BaseUrl)/objects/users"
        Method  = 'GET'
    }   
    $importedAccounts = Invoke-RestMethod @splatAllUsersRestParams 

    # Map the imported data to the account field mappings
    foreach ($importedAccount in $importedAccounts) {
        $personId = if (!([string]::IsNullOrEmpty($importedAccount.rolesAndCompanies))) { $importedAccount.rolesAndCompanies[0].personId } else { $null }
        $importedAccount | Add-Member -MemberType NoteProperty -Name 'personId' -Value $personId
        $importedAccount | Add-Member -MemberType NoteProperty -Name 'additionalContactInfo' -Value @{ 'email' = $importedAccount.contactPoints.additionalContactInfo.eMail }
    
        # Return the result
        Write-Output @{
            AccountReference = @{
                "UserId"   = $importedAccount.UserId
                "PersonId" = $importedAccount.PersonId
            }
            DisplayName      = $importedAccount.Description
            UserName         = $importedAccount.UserName
            Enabled          = if ($importedAccount.userStatus.status -ne 'T') { $true } else { $false }
            Data             = $importedAccount
        }
    }

    Write-Verbose "Account data import completed" -Verbose
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-UBWError -ErrorObject $ex
        if ($null -ne $errorObj.FriendlyMessage) {
            $message = $errorObj.FriendlyMessage
        }
        else {
            $message = $errorObj.ErrorDetails
        }
        $auditMessage = "Could not import account entitlements. Error: $message"        
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $message"
    }
    else {
        $auditMessage = "Could not import account entitlements. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}