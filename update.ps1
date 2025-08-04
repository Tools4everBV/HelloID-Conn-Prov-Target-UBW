#################################################
# HelloID-Conn-Prov-Target-UBW-Update
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

function ConvertTo-UbwFlatObject {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object,
        [string] $Prefix = ""
    )
 
    $result = [ordered]@{}
 
    foreach ($property in $Object.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix`_$($property.Name)" } else { $property.Name }
 
        if ($property.Value -is [pscustomobject]) {
            $flattenedSubObject = ConvertTo-UbwFlatObject -Object $property.Value -Prefix $name
            foreach ($subProperty in $flattenedSubObject.PSObject.Properties) {
                $result[$subProperty.Name] = [string]$subProperty.Value
            }
        }
        else {
            $result[$name] = [string]$property.Value
        }
    }
 
    [PSCustomObject]$result
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

    # Retrieve allUsers for employee    
    $splatAllUsersRestParams = @{
        Headers = $headers
        Uri     = "$($actionContext.Configuration.BaseUrl)/objects/users"
        Method  = 'GET'
    }   
    $allUsers = Invoke-RestMethod @splatAllUsersRestParams

    # Lookup the [account.roleAndCompany.personId]
    $multipleUsers = $allUsers.Where{ $_.rolesAndCompanies.personId -eq "$($actionContext.References.Account.PersonId)" }    

    #region Calulate action    
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        Write-Information "Comparing current account to mapped properties"

        # Change mapping here

        # Define your mapping here for correlatedaccount data to compare
        $correlatedReferenceObject = [PSCustomObject]@{
            userName            = $correlatedAccount.userName           
            defaultLogonCompany = $correlatedAccount.defaultLogonCompany 
            domainUser          = $correlatedAccount.security.domainUser
            description         = $($correlatedAccount.description)
            eMail               = $correlatedAccount.contactpoints.additionalContactInfo.email            
        }

        # Define your mapping here for fieldmapping data to compare
        $accountDifferenceObject = [PSCustomObject]@{
            #userName    = $actionContext.Data.userName            
            userName            = $actionContext.References.Account.userId
            defaultLogonCompany = $actionContext.Data.defaultLogonCompany
            domainUser          = $actionContext.Data.security.domainUser
            description         = $($actionContext.Data.description)
            eMail               = $actionContext.Data.additionalContactInfo.email            
        }

        # To prevent SSO for one account, which disables selection of user when working with UBW
        if (($multipleUsers | Measure-Object).count -gt 1) {
            $correlatedReferenceObject.PSObject.Properties.Remove('domainUser')
            $accountDifferenceObject.PSObject.Properties.Remove('domainUser')
        }

        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedReferenceObject.PSObject.Properties)
            DifferenceObject = @($accountDifferenceObject.PSObject.Properties)
        }  
        $accountPropertiesChanged = Compare-Object @splatCompareProperties -PassThru
        $accountOldProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "<=" }
        $accountNewProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "=>" }

        if ($accountNewProperties) {
            $actionAccount = "UpdateAccount"
            Write-Information "Account property(s) required to update: $($accountNewProperties.Name -join ', ')"
        }
        else {
            $actionAccount = "NoChanges"
        }    
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $actionAccount = "NotFound"
    }
    #endregion Calulate action

    # Process
    switch ($actionAccount) {
        'UpdateAccount' {
            # Create custom object with old and new values (for logging)
            $accountChangedPropertiesObject = [PSCustomObject]@{
                OldValues = @{}
                NewValues = @{}
            }

            foreach ($accountOldProperty in ($accountOldProperties | Where-Object { $_.Name -in $accountNewProperties.Name })) {
                $accountChangedPropertiesObject.OldValues.$($accountOldProperty.Name) = $accountOldProperty.Value
            }

            foreach ($accountNewProperty in $accountNewProperties) {
                $accountChangedPropertiesObject.NewValues.$($accountNewProperty.Name) = $accountNewProperty.Value
            }
            
            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating UBW account with accountReference: [$($actionContext.References.Account.UserId)]"                 
                [System.Collections.Generic.List[object]]$body = @()
                foreach ($prop in $accountNewProperties) {
                    
                    if ($prop.Name -eq 'domainUser') { 
                        $body.Add(
                            [PSCustomObject]@{
                                op    = 'Replace'
                                path  = "security.domainUser"
                                value = "$($prop.value)"
                            }
                        )                       
                    }
                    elseif ($prop.Name -eq 'eMail') {
                        $body.Add(
                            [PSCustomObject]@{
                                op    = 'Replace'
                                path  = "contactPoints"
                                value = @([ordered]@{                                    
                                        'additionalContactInfo' = [ordered]@{
                                            eMail = $($prop.value)     
                                        }
                                        'address'               = [ordered]@{
                                            countryCode = 'NL'
                                        }


                                    })                                
                            }
                        )                        
                    }
                    else {
                        $body.Add(
                            [PSCustomObject]@{
                                op    = 'Replace'
                                path  = "$($prop.name)"
                                value = "$($prop.value)"
                            }
                        )
                    }
                }
                
                #Write-Information ($body | ConvertTo-Json)
                $body = ConvertTo-Json $body -Depth 10
                
                $splatRestParams = @{
                    Headers     = $headers
                    Uri         = "$($actionContext.Configuration.BaseUrl)/users/$($actionContext.References.Account.UserId)"
                    Method      = 'PATCH'                    
                    Body        = $body
                    ContentType = 'application/json-patch+json'                    
                }        
                $updatedAccount = Invoke-RestMethod @splatRestParams                

                $updatedAccount | Add-Member -MemberType NoteProperty -Name 'additionalContactInfo' -Value @{ 'email' = $updatedAccount.contactPoints.additionalContactInfo.eMail }
                $outputContext.Data = $updatedAccount
                
                $correlatedAccount | Add-Member -MemberType NoteProperty -Name 'additionalContactInfo' -Value @{ 'email' = $correlatedAccount.contactPoints.additionalContactInfo.eMail }
                $outputContext.PreviousData = $correlatedAccount
            }
            else {
                Write-Information "[DryRun] Update UBW account with accountReference: [$($actionContext.References.Account.UserId)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($accountNewProperties.Name -join ', ')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to UBW account with accountReference: [$($actionContext.References.Account.UserId)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "UBW account: [$($actionContext.References.Account.UserId)] could not be found, possibly indicating that it could be deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "UBW account with accountReference: [$($actionContext.References.Account.UserId)] could not be found, possibly indicating that it could be deleted"
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
        $auditMessage = "Could not update UBW account. Error: $message"        
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $message"
    }
    else {
        $auditMessage = "Could not update UBW account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}