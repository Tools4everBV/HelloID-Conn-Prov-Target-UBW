#####################################################
# HelloID-Conn-Prov-Target-UBW-Update
#
# Version: 1.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$pd = $personDifferences | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

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
    if (-not($dryRun -eq $true)) {
        Write-Verbose "Updating UBW account: $($aRef) for: $($p.DisplayName)"
        Write-Verbose 'Adding authorization headers'
        $authorization = "$($config.UserName):$($config.Password)"
        $base64Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
        $headers = @{
            Authorization = "Basic $base64Credentials"
        }

        $body = @"
        [
            {
                "path": "",
                "op": "Replace",
                "value": {
                    "description": "$($account.description)"
                }
            }
        ]
"@

        $splatWebRequestParams['Uri'] = "$($config.BaseUrl)/web-api/v1/users/$aRef"
        $splatWebRequestParams['Body'] = $body
        $splatWebRequestParams['Method'] = 'PATCH'
        $splatWebRequestParams['Headers'] = $headers
        $splatWebRequestParams['ContentType'] = 'application/json-patch+json'
        $response = Invoke-WebRequest @$splatWebRequestParams
        if ($response.StatusCode -eq 200){
            $message = "successfully updated UBW account for: $($p.DisplayName) with id: $($aRef)"
            Write-Verbose $message
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = $message
                IsError = $true
            })
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not update UBW account for: $($p.DisplayName). Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not update UBW account for: $($p.DisplayName). Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
} finally {
    $result = [PSCustomObject]@{
        Success      = $success
        Account      = $account
        AuditDetails = $auditMessage
        Auditlogs    = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
