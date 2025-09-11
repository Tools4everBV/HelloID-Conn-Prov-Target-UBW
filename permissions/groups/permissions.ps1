#################################################
# HelloID-Conn-Prov-Target-UBW-Permissions-Roles
# PowerShell V2
#################################################

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
    Write-Information 'Creating authentication headers'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)")))")
    

    Write-Information 'Retrieving permissions'

    # Retrieve all users
    $splatAllRolesRestParams = @{
        Headers = $headers
        Uri     = "$($actionContext.Configuration.BaseUrl)/objects/roles"
        Method  = 'GET'
    }   
    
    $allRoles = Invoke-RestMethod @splatAllRolesRestParams 
    $defaultRoles = $actionContext.Configuration.DefaultRoles.Split(',').Trim()
    $allRoles = $allRoles | Where-Object { $_.status -eq "N" -and $_.roleId -notin ($defaultRoles) -and $_.roleDetailInformations.companyId -eq $actionContext.Configuration.CompanyId } 

    foreach ($permission in $allRoles) {        
        $outputContext.Permissions.Add(
            @{
                DisplayName    = $permission.description
                Identification = @{
                    Id = $permission.roleId                    
                }
            }
        )
    }
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
        $auditMessage = "Could not retrieve UBW permissions. Error: $message"        
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $message"
    }
    else {
        $auditMessage = "Could not retrieve UBW permissions. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}