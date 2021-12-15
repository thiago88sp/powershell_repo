
Write-Output "Enter sourceSubscriptionId"
$sourceSubscriptionId  = read-host

Write-Output "Enter targetSubscriptionId"
$targetSubscriptionId = read-host

Write-Output "Enter sourceResourceGroupName"
$sourceResourceGroupName  = read-host

Write-Output "Enter targetResourceGroupName"
$targetResourceGroupName = read-host

Write-Output "Enter targetVnetName"
$targetVnetName  = read-host

Write-Output "Enter targetVnetResourceGroupName"
$targetVnetResourceGroupName  = read-host


Write-Output "Enter sourceVMName"
$sourceVMName  = read-host

Write-Output "Enter  targetSubnetName"
$targetSubnetName  = read-host




try{stop-transcript|out-null}
catch [System.InvalidOperationException]{}

#region - set all required variables with values
$allDataDisks = @()
$date = Get-Date -UFormat "%m-%d-%Y"
$currentDir = $(Get-Location).Path
$tFile = "$($currentDir)\Migrate_$($sourceVMName)_Transcript_$($date).txt"
$dFormat = "%m-%d-%Y %H:%M:%S"
#end-region

#region - Capture all required information from the VM Details to be used while deploying new VM"
Start-Transcript -Path $tFile -Append -NoClobber
$selectSubscription = Select-AzSubscription -SubscriptionId $sourceSubscriptionId
$vmDetails = Get-AzVM -Name $sourceVMName -ResourceGroupName $sourceResourceGroupName
$vmTags = $vmDetails.Tags
$vmSize = $vmDetails.HardwareProfile.VmSize
$osDiskName = $vmDetails.StorageProfile.OsDisk.Name
$dataDisks = $vmDetails.StorageProfile.DataDisks
if([string]::IsNullOrEmpty($dataDisks)){
    Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: No Data disk attached to VM $sourceVMName" -ForegroundColor Green
}else{
    ForEach($dataDisk in $dataDisks){
        $allDataDisks += $dataDisk.Name
    }
}
#end-region

#region - Stop and deallocate the VM before changing the size
$vmPowerStatus = (Get-AzVM -Name $sourceVMName -ResourceGroupName $sourceResourceGroupName -Status).Statuses.code
if($vmPowerStatus -contains "PowerState/running"){
    $vmRunning = $true
    Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: VM is running, Stopping and Deallocating VM $sourceVMName"  -ForegroundColor Green
    $stopVm = Stop-AzVM -Name $sourceVMName -ResourceGroupName $sourceResourceGroupName -Force -Confirm:$false
    do
    {
        Start-Sleep -Seconds 5
        $vmPowerStatus = (Get-AzVM -Name $sourceVMName -ResourceGroupName $sourceResourceGroupName -Status).Statuses.code
    }while($vmPowerStatus -contains "PowerState/running")
}else{
    Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: VM $sourceVMName is already stopped and deallocated"  -ForegroundColor Green
}
#end-region

#region - copying OS Disk 
Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: Copying VM Disks from source subscription to destination subscription"  -ForegroundColor Green
Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: Copying OS Disk from source subscription to destination subscription"  -ForegroundColor Green
$managedDisk= Get-AzDisk -ResourceGroupName $sourceResourceGroupName -DiskName $osDiskName
$targetLocation = $managedDisk.Location
$osType = $managedDisk.OsType

$selectSubscription = Select-AzSubscription -SubscriptionId $targetSubscriptionId
$diskConfig = New-AzDiskConfig -SourceResourceId $managedDisk.Id -Location $targetLocation -CreateOption Copy  -Tag $vmTags
$newVMDisk = New-AzDisk -Disk $diskConfig -DiskName $osDiskName -ResourceGroupName $targetResourceGroupName 
#end-region

#region - copying Data Disk(s)
if(!([string]::IsNullOrEmpty($allDataDisks))){
    foreach($disk in $allDataDisks){
        Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: Copying VM Disk $disk from source subscription $sourceSubscriptionId to destination subscription $targetSubscriptionId"  -ForegroundColor Green
        $selectSubscription = Select-AzSubscription -SubscriptionId $sourceSubscriptionId
        $managedDisk= Get-AzDisk -ResourceGroupName $sourceResourceGroupName -DiskName $disk
        $selectSubscription = Select-AzSubscription -SubscriptionId $targetSubscriptionId
        $diskConfig = New-AzDiskConfig -SourceResourceId $managedDisk.Id -Location $targetLocation -CreateOption Copy -Tag $vmTags
        $newVMDisk = New-AzDisk -Disk $diskConfig -DiskName $disk -ResourceGroupName $targetResourceGroupName
    }
    Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: All Disks copied"  -ForegroundColor Green
}
#end-region

#region - create a new VM in target subscription with disk copied from source subscription
$selectSubscription = Select-AzSubscription -SubscriptionId $targetSubscriptionId
Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: Creating a new Virtual Machine in subscription $targetSubscriptionId using those copied Disk(s)"  -ForegroundColor Green
$targetVM = New-AzVMConfig -VMName $sourceVMName -VMSize $vmSize
if($osType -eq 'Windows'){
    $managedOSDisk= Get-AzDisk -ResourceGroupName $targetResourceGroupName -DiskName $osDiskName    
    $targetVM = Set-AzVMOSDisk -VM $targetVM -ManagedDiskId $managedOSDisk.Id -CreateOption Attach -Windows
    $vnet = Get-AzVirtualNetwork -Name $targetVnetName -ResourceGroupName $targetVnetResourceGroupName
    $snet = Get-AzVirtualNetworkSubnetConfig -Name $targetSubnetName -VirtualNetwork $vnet
    Write-Host $snet
    $nicName = "$($sourceVMName)_nic01"
    Write-Host $nicName
    $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $targetResourceGroupName -Location $targetLocation -Subnet $snet -Tag $vmTags -Force -Confirm:$false
    $targetVM = Add-AzVMNetworkInterface -VM $targetVM -Id $nic.Id
    $targetVM = Set-AzVMBootDiagnostic -VM $targetVM -Disable
    $newVM = New-AzVM -VM $targetVM -ResourceGroupName $targetResourceGroupName -Location $targetLocation -Tag $vmTags
    Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: Virtual Machine $sourceVMName in subscription $targetSubscriptionId has been deployed"  -ForegroundColor Green
}
#end-region

#region - attach data disks to new VM
if(!([string]::IsNullOrEmpty($allDataDisks))){
    $lun = 1
    foreach($disk in $allDataDisks){        
        Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: Attaching Data Disk $disk"  -ForegroundColor Green
        $selectSubscription = Select-AzSubscription -SubscriptionId $targetSubscriptionId
        $dataDiskInfo = Get-AzDisk -DiskName $disk -ResourceGroupName $targetResourceGroupName
        $targetVMDetails = Get-AzVM -ResourceGroupName $targetResourceGroupName -Name $sourceVMName
        $targetVMDetails = Add-AzVMDataDisk -VM $targetVMDetails -Name $disk -CreateOption Attach -ManagedDiskId $dataDiskInfo.Id  -Lun $lun
        $updateVM = Update-AzVM -ResourceGroupName $targetResourceGroupName -VM $targetVMDetails
        $lun++
    }
    Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: All Disks attached"  -ForegroundColor Green
}
#end-region
Write-Host "[$(Get-Date -UFormat $dFormat)] INFORMATION: Virtual Machine $sourceVMName has been successfully moved from $sourceSubscription to target subscription $targetSubscriptionId"  -ForegroundColor Green
Write-Host (("=") * 100)
Stop-Transcript



