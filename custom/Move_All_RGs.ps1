<#
 .SYNOPSIS
    Change subscription of resources in current environment
 .DESCRIPTION
    This script changes subscriptions ids of all resources in current selected environment, and moves them into new desired subscription.
 .EXAMPLE
     ./devops/ChangeResourceSubscription.ps1 -newSubscriptionId "new-subscription-id"
 
 .PARAMETER newSubscriptionId
    The new subcription id to move resources
 .PARAMETER currentSubscriptionId
    Current subscription id. You dont need to set this if you are running it from devops repo manually, if you are using pipelines or automation, please set this accordingly.
 .PARAMETER currentLocation
    Location of resources to be created. You dont need to set this if you are running it from devops repo manually, if you are using pipelines or automation, please set this accordingly.
 .PARAMETER currentEnvironment
    Current environment you want to move resources from. You dont need to set this if you are running it from devops repo manually, if you are using pipelines or automation, please set this accordingly.
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new subcription id to move resources")]
    [String]$newSubscriptionId,
    
    # IMPORTANT : This parameter fills automatically by executing devops repo scripts manually in terminal, if you are going to use this script in CI/CD please fill this parameter accordingly 
    [Parameter(Mandatory = $false, HelpMessage = "Please specify current subscription id")]
    [String]$currentSubscriptionId,

    # IMPORTANT : This parameter fills automatically by executing devops repo scripts manually in terminal, if you are going to use this script in CI/CD please fill this parameter accordingly 
    [Parameter(Mandatory = $false, HelpMessage = "Please specify resource location of new resources")]
    [String]$currentLocation,

    # IMPORTANT : This parameter fills automatically by executing devops repo scripts manually in terminal, if you are going to use this script in CI/CD please fill this parameter accordingly 
    [Parameter(Mandatory = $false, HelpMessage = "Please specify current environment e.g. : XYZ, DEV, TST")]
    [String]$currentEnvironment
)

if (!$currentSubscriptionId) {
    $currentSubscriptionId = $environmentVariables.subscriptionId
}

if (!$currentLocation) {
    $currentLocation = $location
}

if (!$currentEnvironment) {
    $currentEnvironment = $environmentName
}

# This list contains the wildcard of resource groups which can't be moved to new subscriptions, due to azure limitations. Supported resources for move can be seen here : https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/move-support-resources
$resourcesToIgnore = @(
    "Microsoft.Insights/metricalerts",
    "microsoft.insights/metricalerts",
    "Microsoft.Insights/actiongroups",
    "Microsoft.Web/sites",
    "Microsoft.ApiManagement",
    "microsoft.insights/autoscalesettings",
    "Microsoft.Web/serverFarms",
    "Microsoft.EventGrid/systemTopics"
)

$resourcesToIgnoreQuery = '"' + ($resourcesToIgnore -join '","') + '"'


Write-Host ("Current Environment Subscription Id >> {0}" -f $currentSubscriptionId) -ForegroundColor Green
Write-Host ("New Subscription Id which resources move to >> {0}" -f $newSubscriptionId) -ForegroundColor Magenta
Write-Host "---------------------------------" -ForegroundColor White

# Get all resources for iteration
$resourceGroupList = $(az group list --subscription $currentSubscriptionId --query "[?starts_with(name, '$currentEnvironment')].name" -o tsv)

Write-Host ("Total resource group in this subscription >> {0}" -f $resourceGroupList.Count) -ForegroundColor Yellow
Write-Host "---------------------------------" -ForegroundColor White

# Iterate in every resource group to get resources
foreach ($resourceGroupName in $resourceGroupList) {

    $resourceList = $(az resource list --subscription $currentSubscriptionId --resource-group $resourceGroupName --query "[?!contains('$resourcesToIgnoreQuery', type)].id" -o tsv)

    Write-Host ("Total resource under {0} >> {1}" -f $resourceGroupName, $resourceList.count) -ForegroundColor Cyan

    # If resource group does not exists in new subscription, create a new one

    if ((az group exists --name $resourceGroupName --subscription $newSubscriptionId) -eq 'false') {

        az group create --name $resourceGroupName --location $currentLocation --subscription $newSubscriptionId

        Write-Host ("Resource group {0} does not exist in new subscription, new resource group created" -f $resourceGroupName) -ForegroundColor Yellow

        foreach ($resource in $resourceList) {

            # Move resources one by one to new resource group under new subscription
            # IMPORTANT : This could be done in O(n) instead of O(n^2) if you get resource list first then get parent resource group name from that list, and iterate in one loop instead of two. I wanted to keep it longer to see which resource groups owns which resources, so this provides better understanding.
            
            Move-AzResource -DestinationResourceGroupName $resourceGroupName -ResourceId $resource -DestinationSubscriptionId $newSubscriptionId -force
    
            if ($?) {
                Write-Host ("Resource {0} moved to new subscription >> {1}" -f $resource, $newSubscriptionId) -ForegroundColor Green
            }
            else {
                Write-Host ($_.Exception.message)
                Write-Host ("Moving Resource {0} to new subscription failed >> {1}" -f $resource, $newSubscriptionId) -ForegroundColor Red
                    
                # Stopping script to prevent further damage if anything is wrong
                return
            }     
        }
    
        Write-Host "---------------------------------" -ForegroundColor White
        Write-Host "`r`n" -ForegroundColor White
    }

}

Write-Host ("Operation completed successfully" -f $resourceGroupList.Count) -ForegroundColor Green