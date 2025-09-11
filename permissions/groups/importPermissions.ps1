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
        
    # Retrieve all roles
    $splatAllRolesRestParams = @{
        Headers = $headers
        Uri     = "$($actionContext.Configuration.BaseUrl)/objects/roles"
        Method  = 'GET'
    }   

    $allRoles = Invoke-RestMethod @splatAllRolesRestParams 
    $defaultRoles = $actionContext.Configuration.DefaultRoles.Split(',').Trim()
    $allRoles = $allRoles | Where-Object { $_.roleId -notin ($defaultRoles) -and $_.roleDetailInformations.companyId -eq $actionContext.Configuration.CompanyId } | Select-Object -Property roleId
    $allRoles | Add-Member -Type NoteProperty -Name "members" -Value $null

    # Retrieve all users
    $splatAllUsersRestParams = @{
        Headers = $headers
        Uri     = "$($actionContext.Configuration.BaseUrl)/objects/users"
        Method  = 'GET'
    }   
    $allAccounts = Invoke-RestMethod @splatAllUsersRestParams 

    # Map the imported data to the account field mappings
    foreach ($account in $allAccounts) {
        $personId = if (!([string]::IsNullOrEmpty($account.rolesAndCompanies))) { $account.rolesAndCompanies[0].personId } else { $null }
        if ($null -ne $personId) {        
            $accountReference = [PSCustomObject]@{
                "UserId"   = $account.UserId
                "PersonId" = $PersonId
            }
        
            foreach ($membership in $account.rolesAndCompanies) {
                if ($membership.roleId -notin ($defaultRoles) -and $membership.companyId -eq $actionContext.Configuration.CompanyId -and $membership.roleConnectionStatus -eq 'N' -and $membership.roleId -ne "") {      
                    $roleToAdd = $allRoles | Where-Object { $_.roleId -eq $membership.roleId }
                    $members = @()          
                
                    if ($roleToAdd.PSObject.Properties.Name -contains 'members') {
                        $members += $roleToAdd.members              
                        $members += $accountReference
                        $roleToAdd.members = $members
                    }
                }            
            }
        }    
    }

    foreach ($key in $allRoles.GetEnumerator()) {    
        $references = $key.members | Where-Object { $null -ne $_ }
        if ($references.count -gt 0) {
            
            Write-Output(
                @{
                    AccountReferences   = $references
                    PermissionReference = @{
                        Id = $key.roleId
                    }                   
                    DisplayName         = $key.roleId
                    Description         = $key.roleId                     
                }
            )
        }
    }

    Write-Information 'Target account permission import completed'
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
        $auditMessage = "Could not import permission entitlements. Error: $message"        
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $message"
    }
    else {
        $auditMessage = "Could not import permission entitlements. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}