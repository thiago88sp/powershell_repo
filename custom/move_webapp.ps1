<#
 .SYNOPSIS
    This script moves all webapp and serviceplan from a resource group to a new subscription.
 .DESCRIPTION
    This script moves all webapp and serviceplan from a resource group to a new subscription.
 .EXAMPLE
     ./devops/MoveResource.ps1 -ResourceGroupName ResourceGroupWhere -NewSubscriptionId "new-subscription-id" -CurrentSubscriptionId "current-sub-id"
 
 .PARAMETER SourceSubscriptionId
    The current subscription where the webapp is located.
 .PARAMETER SourceResourceGroupName
    The current resource group where the webapp is located.    
 .PARAMETER webappname
    The name of the web app
 .PARAMETER serviceplanName
    The name of the service plan
 .PARAMETER targetSubscriptionId
    The destination subscription where the resource will be moved.
 .PARAMETER targetResourceGroupName
    The destination resource group where the resource will be moved.
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new subcription id to move resources")]
    [String]$sourceSubscriptionId,

    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new subcription id to move resources")]
    [String]$sourceResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new subcription id to move resources")]
    [String]$webappname,

    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new subcription id to move resources")]
    [String]$serviceplanName,

    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new subcription id to move resources")]
    [String]$targetSubscriptionId,

    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new subcription id to move resources")]
    [String]$targetResourceGroupName
)

Select-AzSubscription -SubscriptionId $sourceSubscriptionId

$webapp = Get-AzResource -ResourceGroupName $sourceResourceGroupName -ResourceName $webappname
$plan = Get-AzResource -ResourceGroupName $sourceResourceGroupName -ResourceName $serviceplanName

Move-AzResource -DestinationSubscriptionId $targetSubscriptionId -DestinationResourceGroupName $targetResourceGroupName -ResourceId $webapp.ResourceId, $plan.ResourceId

Write-Host "Execution Finished."