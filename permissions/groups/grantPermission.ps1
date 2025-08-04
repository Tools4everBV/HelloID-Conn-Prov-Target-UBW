#################################################
# HelloID-Conn-Prov-Target-UBW-GrantPermission
# PowerShell V2
#################################################
#Write-Information $actionContext.References.Account

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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Creating authentication headers'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)")))")
    
    Write-Information 'Verifying if a UBW account exists'

    # Retrieve user
    $splatAllUsersRestParams = @{
        Headers = $headers
        Uri     = "$($actionContext.Configuration.BaseUrl)/users/$($actionContext.References.Account.UserId)"
        Method  = 'GET'
    }   
    $correlatedAccount = Invoke-RestMethod @splatAllUsersRestParams 

    if ($null -ne $correlatedAccount) {
        $action = 'GrantPermission'
    }
    else {
        $action = 'NotFound'
    }
    
    # Process
    switch ($action) {
        'GrantPermission' {
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Granting UBW permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Id)]"
                
                $validFromDate = Get-Date 
                $y = $validFromDate.year
                $m = $validFromDate.month
                $d = $validFromDate.day

                [System.Collections.Generic.List[object]]$body = @()

                $body.Add(
                    [PSCustomObject]@{
                        op    = 'AddOrReplaceById'
                        path  = "roleAndCompany"
                        value = [ordered]@{
                            companyId               = "$($actionContext.Configuration.CompanyId)"
                            personId                = "$($actionContext.References.Account.PersonId)"                            
                            roleConnectionValidFrom = "$($y)-$($m)-$($d)T00:00:00.000Z"
                            roleConnectionValidTo   = "2099-12-31T00:00:00.000Z"
                            roleId                  = "$($actionContext.References.Permission.Id)"
                        }
                    }
                )


                $body = ConvertTo-Json $body -Depth 10

                $splatRestParams = @{
                    Headers     = $headers
                    Uri         = "$($actionContext.Configuration.BaseUrl)/users/$($actionContext.References.Account.UserId)"
                    Method      = 'PATCH'
                    Body        = $body
                    ContentType = 'application/json-patch+json'
                }        
                
                $response = Invoke-RestMethod @splatRestParams
            }

            else {                
                Write-Information "[DryRun] Grant UBW permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Id)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Grant permission [$($actionContext.PermissionDisplayName)] was successful"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "UBW account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "UBW account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
                    IsError = $true
                })
            break
        }
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
        $auditMessage = "Could not grant UBW permission. Error: $message"        
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $message"
    }
    else {
        $auditMessage = "Could not grant UBW permission. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}