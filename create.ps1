#################################################
# HelloID-Conn-Prov-Target-UBW-Create
# PowerShell V2
#################################################
# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Account mapping
# Tables are ordered because UBW doesn't accept the jsonPayload if the order is different
$ubwAccount = [ordered]@{
    alertMedia          = $actionContext.Data.alertMedia
    defaultLogonCompany = $actionContext.Data.defaultLogonCompany
    description         = $actionContext.Data.description
    languageCode        = $actionContext.Data.languageCode
    printer             = $actionContext.Data.printer
    userId              = $actionContext.Data.userId
    userName            = $actionContext.Data.userName    
    security            = [ordered]@{
        domainUser         = $actionContext.Data.security.domainUser
        unit4Id            = ''
        disabledUntil      = $actionContext.Data.security.disabledUntil
        passwordUpdated    = ''
        passwordExpiryDate = "2099-12-31T00:00:00.000Z"
    }
    # userStatus
    userStatus          = [ordered]@{        
        dateFrom = $actionContext.Data.userStatus.dateFrom
        dateTo   = $actionContext.Data.userStatus.dateTo
        status   = $actionContext.Data.userStatus.status
    }    
    # roleAndCompany
    roleAndCompany      = @(
        foreach ($role in $actionContext.Configuration.DefaultRoles.Split(',').Trim()) {
            [ordered]@{            
                companyId               = $actionContext.Data.roleAndCompany.companyId
                personId                = $($actionContext.Data.personId)
                roleConnectionValidFrom = $actionContext.Data.roleAndCompany.roleConnectionValidFrom
                roleConnectionValidTo   = "2099-12-31T00:00:00.000Z"
                roleConnectionStatus    = 'N'
                roleId                  = $role
            }
        }
    )
    # usage
    usage               = [ordered]@{ 
        isAdministrator             = $actionContext.Data.usage.isAdministrator
        availableInMenuAccess       = $actionContext.Data.usage.availableInMenuAccess
        isEnabledForWorkflowProcess = $actionContext.Data.usage.isEnabledForWorkflowProcess    
    }
    # contactPoints
    contactPoints       = @([ordered]@{                        
            additionalContactInfo = [ordered]@{
                contactPerson   = ''
                contactPosition = ''
                eMail           = $actionContext.Data.additionalContactInfo.email
                eMailCc         = ''
                gtin            = ''
                url             = ''
            }
            address               = [ordered]@{
                countryCode   = 'NL'
                place         = ''
                postcode      = ''
                province      = ''
                streetAddress = ''
            }
        })
}

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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Validate correlation configuration    
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        Write-Information 'Creating authentication headers'
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)")))")
    
        # An employee is connected to a user account.
        # Lookup employee. If no employee could be found, an exception will be thrown -> we cannot create a user account.
        $splatEmployeeRestParams = @{
            Headers = $headers
            Uri     = "$($actionContext.Configuration.BaseUrl)/employees/$($actionContext.Data.personId)"            
            Method  = 'GET'
        }
        $responseEmployee = Invoke-RestMethod @splatEmployeeRestParams

        # Retrieve all users
        $splatAllUsersRestParams = @{
            Headers = $headers
            Uri     = "$($actionContext.Configuration.BaseUrl)/objects/users"
            Method  = 'GET'
        }   
        $allUsers = Invoke-RestMethod @splatAllUsersRestParams

        # Lookup the [account.roleAndCompany.personId]
        $correlatedAccount = $allUsers.Where{ $_.rolesAndCompanies.personId -eq "$($actionContext.Data.personId)" }                
    }

    # If the personId on the user account matches with the employee personId -> Correlate
    Write-Information 'Determine if a user needs to be created or correlated'
    
    #if (($correlatedAccount.rolesAndCompanies.personId) -eq ($responseEmployee.personId)) {            
    if (($correlatedAccount | Measure-Object).count -gt 0) {            
        $action = 'CorrelateAccount'
    }
    else {
        # if no user account could be found (i.o. if the $userAccount variable is empty) -> Create
        $action = 'CreateAccount'
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {

                Write-Information "Creating and correlating UBW account for [$($personContext.Person.DisplayName)]"
                
                $body = ConvertTo-Json $ubwAccount -Depth 10
                $splatCreateParams = @{
                    Headers     = $headers
                    Uri         = "$($actionContext.Configuration.BaseUrl)/users"
                    Method      = 'POST'                    
                    Body        = $body
                    ContentType = 'application/json; charset=utf-8'
                }

                $createdAccount = Invoke-RestMethod @splatCreateParams
                
                $outputContext.AccountReference = @{
                    "UserId"   = $createdAccount.userId
                    "PersonId" = $actionContext.Data.personId
                }
                
            }
            else {
                Write-Information "[DryRun] $action UBW account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"                
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference.UserId)]"
            break
        }

        'CorrelateAccount' {
            Write-Information "Correlating UBW account [$($personContext.Person.DisplayName)]"   
            
            if (($correlatedAccount | Measure-Object).count -gt 1) {
                $correlatedAccount = $correlatedAccount | Where-Object { $_.userId -eq $actionContext.Data.userId }
            }
            $outputContext.AccountReference = @{
                "UserId"   = $correlatedAccount.userId
                "PersonId" = $actionContext.Data.personId
            }
            $outputContext.Data.userId = $correlatedAccount.userId
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference.UserId)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
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
        $auditMessage = "Could not create or correlate UBW account. Error: $message"        
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $message"
    }
    else {
        $auditMessage = "Could not create or correlate UBW account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
