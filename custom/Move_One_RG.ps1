param(
    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new subcription id to move resources")]
    [String]$newSubscriptionId,

    [Parameter(Mandatory = $true, HelpMessage = "Please specify the new Resource Group Name")]
    [String]$newResourceGroup,
    
    [Parameter(Mandatory = $true, HelpMessage = "Please specify current subscription id")]
    [String]$currentSubscriptionId,

    [Parameter(Mandatory = $true, HelpMessage = "Please specify current Resource Group Name")]
    [String]$currentResourceGroup
)

# This list contains the wildcard of resource groups which can't be moved to new subscriptions, due to azure limitations. Supported resources for move can be seen here : https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/move-support-resources
$resourcesToIgnore = @(
    "Microsoft.ApiManagement",
    "Microsoft.EventGrid/systemTopics",
    "Microsoft.Insights/actiongroups",
    "microsoft.insights/autoscalesettings",
    "Microsoft.Insights/metricalerts",
    "Microsoft.Network/ddosProtectionPlans",
    "Microsoft.Network/virtualNetworks",
    "Microsoft.Network/virtualNetworks/subnets",
    "Microsoft.Sql/servers/databases",
    "Microsoft.Web/serverFarms",
    "Microsoft.Web/sites"
)

$resourcesToIgnoreQuery = "'" + ($resourcesToIgnore -join "' != type && '") + "'  != type";

Write-Host ("Current Environment Subscription Id >> {0}" -f $currentSubscriptionId) -ForegroundColor Green
Write-Host ("New Subscription Id which resources move to >> {0}" -f $newSubscriptionId) -ForegroundColor Magenta
Write-Host "---------------------------------" -ForegroundColor White

$resourceListJson = $(az resource list --subscription $currentSubscriptionId --resource-group $currentResourceGroup --query "[?$resourcesToIgnoreQuery]" -o json);
$resourceList = $resourceListJson | ConvertFrom-Json;

$appServicePlanListJson = $(az appservice plan list --resource-group $currentResourceGroup --subscription $currentSubscriptionId -o json);
$appServicePlanList = $appServicePlanListJson | ConvertFrom-Json;

$resourceGroupInfoJson = $(az group show --name $currentResourceGroup --subscription $currentSubscriptionId -o json);
$resourceGroupInfo = $resourceGroupInfoJson | ConvertFrom-Json;

$currentLocation = $resourceGroupInfo.location;
$currentTags = $resourceGroupInfo.tags;
$newTags = @();

$totalResources = $resourceList.count + $appServicePlanList.count;

Write-Host ("Total resource under {0} >> {1}" -f $currentResourceGroup, $totalResources) -ForegroundColor Cyan;

# If resource group does not exists in new subscription, create a new one
if ((az group exists --name $newResourceGroup --subscription $newSubscriptionId) -eq 'false') {
    az group create --name $newResourceGroup --location $currentLocation --subscription $newSubscriptionId
    Write-Host ("Resource group {0} does not exist in new subscription, new resource group created" -f $newResourceGroup) -ForegroundColor Yellow
}
else {
    Write-Host "Resource Group $newResourceGroup already exists in new subscription" -ForegroundColor Green;
}

$newResourceGroupID = "/subscriptions/$newSubscriptionId/resourceGroups/$newResourceGroup";

foreach ($Tag in $currentTags.PSObject.Properties) {
    $TagName = $Tag.Name;
    $TagValue = $Tag.Value;

    if ($TagName.Trim().Length -gt 0) {
        $newTags += "$TagName=$TagValue"
    }    
}

if ($newTags.Length -gt 0) {
    az tag create --resource-id $newResourceGroupID --tags $newTags --subscription $newSubscriptionId;
    if ($?) {
        Write-Host "Tags copied from source resource group to target resource group" -ForegroundColor Green;
    }
    else {
        Write-Host ($_.Exception.message);
        Write-Host "Unable to copy source resource group Tags";
    }
}
else {
    Write-Host "The source resource group does not have tags to be copied" -ForegroundColor Yellow;
}


foreach ($appServicePlan in $appServicePlanList) {
    $appServicePlanId = $appServicePlan.id;
    $appServiceToMove = @($appServicePlanId);

    $webAppListJson = $(az webapp list --resource-group $currentResourceGroup --subscription $currentSubscriptionId --query "[?appServicePlanId == '$appServicePlanId']" -o json);
    $webAppList = $webAppListJson | ConvertFrom-Json;

    $appFunctionListJson = $(az functionapp list --resource-group $currentResourceGroup --subscription $currentSubscriptionId --query "[?appServicePlanId == '$appServicePlanId']" -o json);
    $appFunctionList = $appFunctionListJson | ConvertFrom-Json;

    foreach ($webApp in $webAppList) {
        $webAppID = $webApp.id;
        $appServiceToMove += $webAppID;
    }

    foreach ($appFunction in $appFunctionList) {
        $appFunctionID = $appFunction.id;
        $appServiceToMove += $appFunctionID;
    }

    az resource move --destination-group $newResourceGroup --destination-subscription-id $newSubscriptionId --subscription $currentSubscriptionId --ids $appServiceToMove;

    if ($?) {
        Write-Host ("Resources {0} moved to new subscription >> {1}" -f  ($appServiceToMove -join "' | '"), $newSubscriptionId) -ForegroundColor Green
    }
    else {
        Write-Host ($_.Exception.message)
        Write-Host ("Moving Resources {0} to new subscription failed >> {1}" -f ($appServiceToMove -join "' | '"), $newSubscriptionId) -ForegroundColor Red
        return
    }  
}

foreach ($resource in $resourceList) {
    $resourceID = $resource.id;
    $resourceType = $resource.type;

    az resource move --destination-group $newResourceGroup --destination-subscription-id $newSubscriptionId --subscription $currentSubscriptionId --ids $resourceID;
    #Move-AzResource -DestinationResourceGroupName $newResourceGroup -ResourceId $resourceID -DestinationSubscriptionId $newSubscriptionId -force

    if ($?) {
        Write-Host ("Resource {0} moved to new subscription >> {1}" -f $resourceID, $newSubscriptionId) -ForegroundColor Green;
    }
    else {
        Write-Host ($_.Exception.message);
        Write-Host ("Moving Resource {0} to new subscription failed >> {1}" -f $resourceID, $newSubscriptionId) -ForegroundColor Red;
        # Stopping script to prevent further damage if anything is wrong
        return
    }     
}

Write-Host "---------------------------------" -ForegroundColor White
Write-Host "`r`n" -ForegroundColor White

Write-Host ("Operation completed successfully") -ForegroundColor Green