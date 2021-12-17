$sourceSubscriptionId = Read-Host -Prompt 'Enter sourceSubscriptionId';
$sourceResourceGroupName = Read-Host -Prompt 'Enter sourceResourceGroupName';
$targetSubscriptionId = Read-Host -Prompt 'Enter targetSubscriptionId';
$targetResourceGroupName = Read-Host -Prompt 'Enter targetResourceGroupName';

$resourceListJson = $(az resource list --subscription $sourceSubscriptionId --resource-group $sourceResourceGroupName -o json);
$resourceList = $resourceListJson | ConvertFrom-Json;

$vnetDDoSList = @();
$ddosProtectionPlanID = "";

foreach ($resource in $resourceList) {
    $resourceType = $resource.type;
    $resourceName = $resource.name;
    $resourceID = $resource.id;

    if ($resourceType -eq "Microsoft.Network/virtualNetworks") {
        $vnetInfoJson = $(az network vnet show --name $resourceName --resource-group $sourceResourceGroupName --subscription $sourceSubscriptionId -o json);
        $vnetInfo = $vnetInfoJson | ConvertFrom-Json;

        $enableDdosProtection = $vnetInfo.enableDdosProtection;

        if ($enableDdosProtection -eq $True) {
            $ddosProtectionPlanID = $vnetInfo.ddosProtectionPlan.id;

            $vnetDDoSList += $resourceID;
            $outputDisableDDoS = $(az network vnet update --resource-group $sourceResourceGroupName --name $resourceName --subscription $sourceSubscriptionId --ddos-protection false --remove ddosProtectionPlan -o json);
            Write-Host $outputDisableDDoS;
        }

        $outputMove = $(az resource move --ids $resourceID --destination-group $targetResourceGroupName --destination-subscription-id $targetSubscriptionId -o json);
        Write-Host $outputMove;

        if ($enableDdosProtection -eq $True) {
            $outputEnableDDoS = $(az network vnet update --resource-group $targetResourceGroupName --name $resourceName --subscription $targetSubscriptionId --ddos-protection true --ddos-protection-plan $ddosProtectionPlanID -o json);
            Write-Host $outputEnableDDoS;
        }
    }
}

Write-Host $vnetDDoSList;