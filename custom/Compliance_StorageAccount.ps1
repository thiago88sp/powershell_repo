$currentSubscriptionId = Read-Host -Prompt 'Enter currentSubscriptionId';
$storageVnetName = Read-Host -Prompt 'Enter storageVnetName';
$storageSubnetName = Read-Host -Prompt 'Enter storageSubnetName';

$remediateStorage = $false;

$resourceGroupListJson = $(az group list --subscription $currentSubscriptionId -o json);
$resourceGroupList = $resourceGroupListJson | ConvertFrom-Json;

foreach ($resourceGroup in $resourceGroupList) {
    $resourceGroupName = $resourceGroup.name;
    
    $resourceListJson = $(az resource list --subscription $currentSubscriptionId --resource-group $resourceGroupName -o json);
    $resourceList = $resourceListJson | ConvertFrom-Json;

    foreach ($resource in $resourceList) {
        $resourceType = $resource.type;
        $resourceName = $resource.name;
        $resourceID = $resource.id;
        $resourceLocation = $resource.location;

        if ( ($resourceType -eq "Microsoft.Storage/storageAccounts") -or ($resourceType -eq "Microsoft.ClassicStorage/storageAccounts") ) {
            $storageInfoJson = $(az storage account show --name $resourceName --subscription $currentSubscriptionId --resource-group $resourceGroupName -o json);
            $storageInfo = $storageInfoJson | ConvertFrom-Json;

            $networkRuleSetDefaultAction = $storageInfo.networkRuleSet.defaultAction;
            $enableHttpsTrafficOnly = $storageInfo.enableHttpsTrafficOnly;
            $allowBlobPublicAccess = $storageInfo.allowBlobPublicAccess;
            $privateEndpointConnections = $storageInfo.privateEndpointConnections;
            $virtualNetworkRules = $storageInfo.networkRuleSet.virtualNetworkRules;
            
            #Access to storage accounts with firewall and virtual network configurations should be restricted
            if ($networkRuleSetDefaultAction -ne "Allow") {
                Write-Host "Storage Account '$resourceName' restrict network access";
            }
            else {
                Write-Host "Storage Account '$resourceName' does not restrict network access";
                if ($remediateStorage) {
                    $outputRestrictNetworkAccess = $(az storage account update --default-action Deny --name $resourceName --resource-group $resourceGroupName --subscription $currentSubscriptionId);
                    Write-Host $outputRestrictNetworkAccess;
                }
            }

            #Secure transfer to storage accounts should be enabled
            if ($enableHttpsTrafficOnly -eq $true) {
                Write-Host "Storage Account '$resourceName' allow Https Traffic Only";
            }
            else {
                Write-Host "Storage Account '$resourceName' allow Http and Https Traffic";
                if ($remediateStorage) {
                    $outputHttpsOnly = $(az storage account update --https-only true --name $resourceName --resource-group $resourceGroupName --subscription $currentSubscriptionId);
                    Write-Host $outputHttpsOnly;
                }
            }

            #Storage account public access should be disallowed
            if ($allowBlobPublicAccess -eq $false) {
                Write-Host "Storage Account '$resourceName' doesn't allow Public Access";
            }
            else {
                Write-Host "Storage Account '$resourceName' allow Public Access";
                if ($remediateStorage) {
                    $outputPublicAccess = $(az storage account update --allow-blob-public-access false --name $resourceName --resource-group $resourceGroupName --subscription $currentSubscriptionId);
                    Write-Host $outputPublicAccess;
                }
            }

            #Storage account should use a private link connection
            if ($privateEndpointConnections.Length -gt 0) {
                Write-Host "Storage Account '$resourceName' have Private Endpoint Connections";
            }
            else {
                Write-Host "Storage Account '$resourceName' doesn't have Private Endpoint Connections";
                if ($remediateStorage) {
                    $outputSubnetPolicie = $(az network vnet subnet update --resource-group $resourceGroupName --name $storageSubnetName --vnet-name $storageVnetName --subscription $subscription --disable-private-endpoint-network-policies true);
                    Write-Host $outputSubnetPolicie;

                    $outputPrivateEndpoint = $(az network private-endpoint create --resource-group $resourceGroupName --name "$resourceName-PeP" --vnet-name $storageVnetName --subnet $storageSubnetName --private-connection-resource-id $resourceID --connection-name PePConnection --location $resourceLocation --subscription $subscription --group-id "blob");
                    Write-Host $outputPrivateEndpoint;
                }
            }

            #Storage accounts should be migrated to new Azure Resource Manager resources
            if ($resourceType -eq "Microsoft.Storage/storageAccounts") {
                Write-Host "Storage Account '$resourceName' is under the provider Microsoft.Storage";
            }
            else {
                Write-Host "Storage Account '$resourceName' is under the provider Microsoft.ClassicStorage";
                if ($remediateStorage) {
                    #Sign in to the Resource Manager model.
                    #Login-AzureRmAccount
                    #Sign in the classic model
                    #Add-AzureAccount
                    Move-AzureStorageAccount -Prepare -StorageAccountName $resourceName;
                    #Move-AzureStorageAccount -Abort -StorageAccountName $resourceName;
                    Move-AzureStorageAccount -Commit -StorageAccountName $resourceName;
                }
            }

            #Storage accounts should restrict network access using virtual network rules
            if ($virtualNetworkRules.Length -gt 0) {
                Write-Host "Storage Account '$resourceName' restrict network access using virtual network"
            }
            else {
                Write-Host "Storage Account '$resourceName' doesn't restrict network access using virtual network"
                if ($remediateStorage -and $storageVnetName -and $storageSubnetName) {
                    $outputVirtualNetwork = $(az storage account network-rule add --resource-group $resourceGroupName --account-name $resourceName --vnet-name $storageVnetName --subnet $storageSubnetName --subscription $currentSubscriptionId);
                    Write-Host $outputVirtualNetwork;
                }
            }
            break;
        }
    }
    break;
}
