<#
.SYNOPSIS
This script is designed to query all work items for a given Organization/Project in AzureDevOps for the 'CascadeTags' tag.
For each work item that is found with the CasecadeTags tag, all of that work items' tags are added to the Child items associated with that work item.
For example, if a Feature with tags: 'CascadeTags' and 'Incident Response' exists with a Child User Story with tags 'Research' and 'Blocked', the User Story
will be updated to contain the tags: 'Research', 'Blocked', and 'Incident Response'. Note that CascadeTags is not cascaded.
#>

<#
.SYNOPSIS
Retrieves child work items for a given parent work item in Azure DevOps.

.DESCRIPTION
This function queries the Azure DevOps REST API to retrieve child work items for a given parent work item.

.PARAMETER OrganizationName
The name of the Azure DevOps organization.

.PARAMETER ProjectName
The name of the Azure DevOps project.

.PARAMETER WorkItemId
The ID of the parent work item.

.PARAMETER PersonalAccessToken
The personal access token (PAT) to authenticate to the Azure DevOps REST API.
#>
function Get-AzureDevOpsChildItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OrganizationName,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,

        [Parameter(Mandatory = $true)]
        [string]$PersonalAccessToken
    )

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalAccessToken)"))

    $headers = @{
        Authorization = "Basic $($base64AuthInfo)"
    }

    $url = "https://dev.azure.com/$($OrganizationName)/$($ProjectName)/_apis/wit/wiql?api-version=6.1-preview.2"

    $query = @"
    {
        "query": "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] <> '' AND [System.Parent] = $WorkItemId"
    }
"@

    $apiParams = @{
        Uri         = $url
        Method      = 'Post'
        ContentType = 'application/json'
        Headers     = $headers
        Body        = $query
    }

    try {
        $response = Invoke-RestMethod @apiParams

        $workItemIds = $response.workItems.id

        if ($workItemIds.Count -eq 0) {
            Write-Output "No child items found for Work Item ID: $WorkItemId"
        }
        else {
            $ids = $workItemIds -join ','
            $urlDetails = "https://dev.azure.com/$($OrganizationName)/$($ProjectName)/_apis/wit/workitems?ids=$ids&api-version=6.1-preview.3"
            $childItems = Invoke-RestMethod -Uri $urlDetails -Method Get -ContentType "application/json" -Headers $headers

            foreach ($result in $childItems.value) {
                [PSCustomObject]@{
                    WorkItemId = $result.id
                    Revision   = $result.rev
                    Fields     = $result.fields
                }
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Error "Error occurred while fetching child items: $errorMessage"
    }
}

<#
.SYNOPSIS
Retrieves work items from Azure DevOps with a specific tag.

.DESCRIPTION
This function queries the Azure DevOps REST API to retrieve work items with a specific tag.

.PARAMETER OrganizationName
The name of the Azure DevOps organization.

.PARAMETER ProjectName
The name of the Azure DevOps project.

.PARAMETER TagName
The tag to search for in work items.

.PARAMETER PersonalAccessToken
The personal access token (PAT) to authenticate to the Azure DevOps REST API.
#>
function Get-AzureDevOpsWorkItemsByTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OrganizationName,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $true)]
        [string]$PersonalAccessToken
    )

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalAccessToken)"))

    $headers = @{
        Authorization = "Basic $($base64AuthInfo)"
    }

    $url = "https://dev.azure.com/$($OrganizationName)/$($ProjectName)/_apis/wit/wiql?api-version=6.1-preview.2"

    $query = @"
{
"query": "SELECT [System.Id], [System.Tags] FROM WorkItems WHERE [System.Tags] CONTAINS '$TagName'"
}
"@

    $apiParams = @{
        Uri         = $url
        Method      = 'Post'
        ContentType = 'application/json'
        Headers     = $headers
        Body        = $query
    }

    try {
        $response = Invoke-RestMethod @apiParams

        $workItemIds = $response.workItems.id

        if ($workItemIds.Count -eq 0) {
            Write-Warning "No Work Items found with the tag: $TagName"
        }
        else {
            $ids = $workItemIds -join ','
            $urlDetails = "https://dev.azure.com/$($OrganizationName)/$($ProjectName)/_apis/wit/workitems?ids=$ids&api-version=6.1-preview.3"
            $workItems = Invoke-RestMethod -Uri $urlDetails -Method Get -ContentType "application/json" -Headers $headers

            foreach ($result in $workItems.value) {
                [PSCustomObject]@{
                    WorkItemId = $result.id
                    Revision   = $result.rev
                    Fields     = $result.fields
                }
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Error "Error occurred while fetching Work Items: $errorMessage"
    }
}

<#
.SYNOPSIS
Adds a tag to a work item in Azure DevOps.

.DESCRIPTION
This function updates a work item in Azure DevOps by adding a new tag to it.

.PARAMETER OrganizationName
The name of the Azure DevOps organization.

.PARAMETER PersonalAccessToken
The personal access token (PAT) to authenticate to the Azure DevOps REST API.

.PARAMETER TagName
The tag to be added to the work item.

.PARAMETER WorkItemId
The ID of the work item to which the tag will be added.

#>
function Add-TagToWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OrganizationName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PersonalAccessToken,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$TagName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$WorkItemId
    )

    $encodedPAT = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalAccessToken)"))

    foreach ($id in $WorkItemId) {
        $workItemUrl = "https://dev.azure.com/$($OrganizationName)/_apis/wit/workitems/$($id)?api-version=7.0"

        $headers = @{
            Authorization = "Basic $encodedPAT"
        }

        $existingWorkItem = Invoke-RestMethod -Method Get -Uri $workItemUrl -Headers $headers

        $existingTags = $existingWorkItem.fields.'System.Tags'
        $newTags = "$($existingTags); $($TagName -join '; ')"

        $body = @(
            @{
                op    = "add"
                path  = "/fields/System.Tags"
                value = $newTags
            }
        ) | ConvertTo-Json

        # This is necessary as the PATCH request expects a JSON array, but PowerShell outputs a single object, {}.
        $body = "[$body]"

        $patchUrl = "https://dev.azure.com/$($OrganizationName)/_apis/wit/workitems/$($id)?api-version=7.0"
        $contentType = "application/json-patch+json"

        try {
            Invoke-RestMethod -Method Patch -Uri $patchUrl -Headers $headers -ContentType $contentType -Body $body
            Write-Host "Added tag '$($TagName)' to work item with ID: $($id)" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to add tag to work item with ID: $($id). Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

}

<#
.SYNOPSIS
Cascades tags from parent work items to child work items.

.DESCRIPTION
This function finds work items with the 'CascadeTags' tag, and then adds the tags from the parent work item to its child work items.

.PARAMETER OrganizationName
The name of the Azure DevOps organization.

.PARAMETER ProjectName
The name of the Azure DevOps project.

.PARAMETER PersonalAccessToken
The personal access token (PAT) to authenticate to the Azure DevOps REST API.
#>
function Invoke-CascadeTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $OrganizationName,

        [Parameter(Mandatory = $true)]
        [string] $ProjectName,

        [Parameter(Mandatory = $true)]
        [string] $PersonalAccessToken
    )

    $CascadeTagsWorkItems = Get-AzureDevOpsWorkItemsByTag -OrganizationName $OrganizationName -ProjectName $ProjectName -TagName 'CascadeTags' -PersonalAccessToken $PersonalAccessToken

    foreach ($WorkItem in $CascadeTagsWorkItems) {
        [string[]]$Tags = $WorkItem.fields | Select-Object -ExpandProperty 'System.Tags' | ForEach-Object { $PSItem.split('; ') }
        $Tags = $Tags | Where-Object -FilterScript { $_ -notlike 'CascadeTags' }
        if ($null -eq $Tags -or ($Tags.Length -eq 0)) { continue }
        Get-AzureDevOpsChildItems -OrganizationName $OrganizationName -ProjectName $ProjectName -WorkItemId $WorkItem.WorkItemId -PersonalAccessToken $PersonalAccessToken | Add-TagToWorkItem -OrganizationName $OrganizationName -PersonalAccessToken $PersonalAccessToken -TagName $Tags
    }
}

$OrganizationName = 'YourOrganizationName'
$ProjectName = 'YourProjectName'
$PersonalAccessToken = 'YourPersonalAccessToken'

Invoke-CascadeTags -OrganizationName $OrganizationName -ProjectName $ProjectName -PersonalAccessToken $PersonalAccessToken