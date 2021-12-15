#####################################################
# HelloID-Conn-Prov-Target-UBW-Create
#
# Version: 1.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
# Tables are ordered because UBW doesn't accept the jsonPayload if the order is different
$account = [ordered]@{
    alertMedia          = ''
    defaultLogonCompany = ''
    description         = ''
    languageCode        = ''
    printer             = ''
    userId              = ''
    userName            = ''

    security = [ordered]@{
        domainUser         = ''
        unit4Id            = ''
        disabledUntil      = ''
        passwordUpdated    = ''
        passwordExpiryDate = ''

    }

    # userStatus
    userStatus = [ordered]@{
        dateFrom = ''
        dateTo   = ''
        status   = ''
    }

    # roleAndCompany
    roleAndCompany = @([ordered]@{
        companyId               = ''
        personId                = ''
        roleConnectionValidFrom = ''
        roleConnectionValidTo   = ''
        roleConnectionStatus    = ''
        roleId                  = ''
    })

    # contactPoints
    contactPoints = @([ordered]@{
            additionalContactInfo = [ordered]@{
            contactPerson   = ''
            contactPosition = ''
            eMail           = ''
            eMailCc         = ''
            gtin            = ''
            url             = ''
        }
        address = [ordered]@{
            countryCode   = ''
            place         = ''
            postcode      = ''
            province      = ''
            streetAddress = ''
        }
    })
}

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if a user must be created or correlated
    Write-Verbose 'Adding authorization headers'
    $authorization = "$($config.UserName):$($config.Password)"
    $base64Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
    $splatRestParams = @{
        Headers = @{
            Authorization = "Basic $base64Credentials"
        }
    }

    # An employee is connected to a user account.
    # Lookup employee. If no employee could be found, an exception will be thrown -> we cannot create a user account.
    $splatRestParams['Uri'] = "$($config.BaseUrl)/web-api/v1/employees/$($account.roleAndCompany.personId)"
    $splatRestParams['Method'] = 'GET'
    $responseEmployee = Invoke-RestMethod @splatRestParams

    # Retrieve all users
    $splatRestParams['Uri'] = "$($config.BaseUrl)/web-api/v1/objects/users"
    $splatRestParams['Method'] = 'GET'
    $allUsers = Invoke-RestMethod @splatRestParams

    # Lookup the [account.roleAndCompany.personId]
    $userAccount = $allUsers.Where{$_.rolesAndCompanies.personId -eq "$($account.roleAndCompany.personId)"}

    # If the personId on the user account matches with the employee personId -> Correlate
    if (($userAccount) -eq ($responseEmployee.personId)){
        Write-Verbose "User account for: [$($p.DisplayName)] found with personId: [$($responseEmployee.personId)], switching to 'correlate'"
        $action = 'Correlate'
    } elseif (-Not($userAccount)) {
        # if no user account could be found (i.o. if the $userAccount variable is empty) -> Create
        Write-Verbose "No user account for: [$($p.DisplayName)] found, switching to 'create'"
        $action = 'Create'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true){
        $auditMessage = "$action UBW account for: [$($p.DisplayName)], will be executed during enforcement"
    }

    if (-not($dryRun -eq $true)){
        switch ($action) {
            'Create' {
                Write-Verbose "Creating UBW account for: [$($p.DisplayName)]"
                $body = $account | ConvertTo-Json -Depth 10

                $splatRestParams['Uri'] = "$($config.BaseUrl)/web-api/v1/users"
                $splatRestParams['Body'] = $body
                $splatRestParams['Method'] = 'POST'
                $splatRestParams['ContentType'] = 'application/json'
                $responseCreateUser = Invoke-RestMethod @splatRestParams
                $accountReference = $responseCreateUser.userId
                break
            }

            'Correlate'{
                Write-Verbose "Correlating UBW account for: [$($p.DisplayName)]"
                $accountReference = $($userAccount.userId)
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action account for: [$($p.DisplayName)] was successful. AccountReference is: [$accountReference]"
            IsError = $false
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not $action UBW account for: [$($p.DisplayName)]. Error: [$($errorObj.ErrorMessage)]"
    } else {
        $errorMessage = "Could not $action UBW account for: [$($p.DisplayName)]. Error: [$($ex.Exception.Message)]"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
} finally {
   $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        AuditDetails     = $auditMessage
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
