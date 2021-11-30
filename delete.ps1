#####################################################
# HelloID-Conn-Prov-Target-UBW-Delete
#
# Version: 1.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

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
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true){
        $auditMessage = "Delete UBW account for: [$($p.DisplayName)], will be executed during enforcement"
    }

     if (-not($dryRun -eq $true)) {
        Write-Verbose "Deleting UBW account: $($aRef) from: $($p.DisplayName)"
        Write-Verbose 'Adding authorization headers'
        $authorization = "$($config.UserName):$($config.Password)"
        $base64Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
        $headers = @{
            Authorization = "Basic $base64Credentials"
        }

        $splatParams['Uri'] = "$($config.BaseUrl)/web-api/v1/users/$aRef"
        $splatParams['Method'] = 'GET'
        $splatParams['Headers'] = $headers
        $null = Invoke-RestMethod @splatRestParams
        $splatWebRequestParams = @{
            Uri     = "$($config.BaseUrl)/web-api/v1/users/$aRef)"
            Method  = 'DELETE'
            Headers = $headers
        }
        $responseDeleteUser = Invoke-WebRequest @splatWebRequestParams
        if ($responseDeleteUser.StatusCode -eq 200){
            $message = "successfully deleted UBW account for: $($p.DisplayName) with userId: $($aRef)"
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
        $errorMessage = "Could not delete UBW account for: $($p.DisplayName). Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not delete UBW account for: $($p.DisplayName). Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
} finally {
    $result = [PSCustomObject]@{
        Success      = $success
        AuditDetails = $auditMessage
        Auditlogs    = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
