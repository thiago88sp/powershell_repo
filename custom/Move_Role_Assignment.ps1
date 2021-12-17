$sourceSubscriptionId = Read-Host -Prompt 'Enter sourceSubscriptionId';
$sourceResourceGroupName = Read-Host -Prompt 'Enter sourceResourceGroupName';
$targetSubscriptionId = Read-Host -Prompt 'Enter targetSubscriptionId';
$targetResourceGroupName = Read-Host -Prompt 'Enter targetResourceGroupName';
$targetResourceGroupID = "/subscriptions/$targetSubscriptionId/resourceGroups/$targetResourceGroupName";

$roleAssignmentListJson = $(az role assignment list --resource-group $sourceResourceGroupName --subscription $sourceSubscriptionId -o json);
$roleAssignmentList = $roleAssignmentListJson | ConvertFrom-Json;

foreach ($roleAssignment in $roleAssignmentList) {
    $principalId = $roleAssignment.principalId;
    $roleDefinitionId = $roleAssignment.roleDefinitionId;

    $outputRoleAssignment = $(az role assignment create --scope $targetResourceGroupID --assignee $principalId --role $roleDefinitionId --subscription $targetSubscriptionId);
    Write-Host $outputRoleAssignment;
}