<# Requires -Modules Az #>
#Install-Module -Name ImportExcel
param(
    [Parameter(Mandatory = $false, HelpMessage = "Enter Subscription ID List")]
    [String[]]$InputSubscriptionIDList,
    [Parameter(Mandatory = $false, HelpMessage = "Enter Resource Group Name List")]
    [String[]]$InputResourceGroupNameList,
    [Parameter(Mandatory = $false, HelpMessage = "Enter VM List")]
    [String[]]$InputVMList,
    [Parameter(Mandatory = $false, HelpMessage = "Enter the Interval in days")]
    [Int]$IntervalInDays = 7,
    [Parameter(Mandatory = $false, HelpMessage = "Enter the Time Grain")]
    [ValidateSet("00:01:00", "00:05:00", "00:15:00", "00:30:00", "01:00:00", "06:00:00", "12:00:00", "24:00:00")]
    [String]$TimeGrain = "00:05:00",
    [Parameter(Mandatory = $false, HelpMessage = "Add Right Size Tag on VM?")]
    [Bool]$AddRightSizeTag = $False,
    [Parameter(Mandatory = $false, HelpMessage = "File type to export")]
    [ValidateSet("csv", "xlsx", IgnoreCase = $true)]
    [String]$ExportFileType = "csv"
)
$InformationPreference = "SilentlyContinue";
$dFormat = "%Y-%m-%d %H:%M:%S";
$currentDir = $(Get-Location).Path;
$RightSizeTag = @{"Candidate" = "Right Size"};
$FileExport = (Join-Path -Path $currentDir -ChildPath "CpuMemoryUtilization-$(Get-Date -UFormat "%Y-%m-%d-%H-%M-%S").$($ExportFileType)");
$InfoExport = @();
if ([Environment]::UserName -eq "Administrator") {
    Import-Module Az;
    Connect-AzAccount -Identity;
    $VMList = $InputVMList.Split(",");
    $SubscriptionIDList = $InputSubscriptionIDList.Split(",");
}
If ( ($ExportFileType -eq "xlsx") -and (-not(Get-InstalledModule "ImportExcel" -ErrorAction SilentlyContinue)) ) {
    Write-Host ("[$(Get-Date -UFormat $dFormat)] Instalando módulo `"ImportExcel`" para exportar o arquivo final") -ForegroundColor Yellow;
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}
function FetchMetricsCPU() {
    param(
        [Parameter()]
        [String]$ResourceID,
        [Parameter()]
        [Int]$Interval = 7,
        [Parameter()]
        [String]$TimeGrain = "00:05:00"
    )
    $MetricsTypes = @("Average", "Maximum");
    $MetricsData = @{
        "ResourceId" = $ResourceID
        "MetricName" = "Percentage CPU"
        "TimeGrain" = $TimeGrain
        "StartTime" = (Get-Date).AddDays($Interval * -1)
        "EndTime" = (Get-Date)
    }
    $Sum = 0;
    $Count = 0;
    $Max = 0;
    foreach ($MetricsType in $MetricsTypes) {
        $MetricsData.Add("AggregationType", $MetricsType);
        $Metrics = (Get-AzMetric @MetricsData -WarningAction SilentlyContinue);
        foreach ($Metric in $Metrics) {
            foreach ($Timeseries in $Metric.Timeseries) {
                foreach ($Data in $Timeseries.Data) {
                    if (!$Data.Average) {
                        $Data.Average = 0;
                    }
                    if (!$Data.Maximum) {
                        $Data.Maximum = 0;
                    }
                    if ($Data.Maximum -gt $Max) {
                        $Max = [Float]$Data.Maximum;
                    }
                    if ( ($MetricsType -eq "Average") -and ($Data.Average -gt 0) ) {
                        $Count += 1;
                        $Sum = $Sum + [Float]$Data.Average;
                    }
                }
            }
        }
        $MetricsData.Remove("AggregationType");
    }
    if ( ($Count -eq 0) -or ($Sum -eq 0) ) {
        $Count = 1;
        $Sum = 1;
    }
    $Data = @{
        "ResourceID" = $ResourceID
        "Average" = ($Sum/$Count)
        "Max" = $Max
    }
    return $Data;
}
function FetchMetricsMemory() {
    param(
        [Parameter()]
        [String]$ResourceID,
        [Parameter()]
        [Int]$Interval = 7,
        [Parameter()]
        [String]$TimeGrain = "00:05:00"
    )
    $MetricsTypes = @("Average", "Maximum", "Minimum");
    $MetricsData = @{
        "ResourceId" = $ResourceID
        "MetricName" = "Available Memory Bytes"
        "TimeGrain" = $TimeGrain
        "StartTime" = (Get-Date).AddDays($Interval * -1)
        "EndTime" = (Get-Date)
    }
    $Sum = 0;
    $Count = 0;
    $Max = 0;
    $Min = 999999999999999999999999999999999999999999999999999;
    foreach ($MetricsType in $MetricsTypes) {
        $MetricsData.Add("AggregationType", $MetricsType);
        $Metrics = (Get-AzMetric @MetricsData -WarningAction SilentlyContinue);
        foreach ($Metric in $Metrics) {
            foreach ($Timeseries in $Metric.Timeseries) {
                foreach ($Data in $Timeseries.Data) {
                    if (!$Data.Average) {
                        $Data.Average = 0;
                    }
                    if (!$Data.Maximum) {
                        $Data.Maximum = 0;
                    }
                    if ($Data.Maximum -gt $Max) {
                        $Max = [Float]$Data.Maximum;
                    }
                    if ( ($MetricsType -eq "Minimum") -and ($Data.Minimum -lt $Min) -and ($Data.Minimum -gt 0) ) {
                        $Min = [Float]$Data.Minimum;
                    }
                    if ( ($MetricsType -eq "Average") -and ($Data.Average -gt 0) ) {
                        $Count += 1;
                        $Sum = $Sum + [Float]$Data.Average;
                    }
                }
            }
        }
        $MetricsData.Remove("AggregationType");
    }
    if ( ($Count -eq 0) -or ($Sum -eq 0) ) {
        $Count = 1;
        $Sum = 1;
    }
    $Data = @{
        "ResourceID" = $ResourceID
        "Average" = ((($Sum/$Count)/1024)/1024)
        "Max" = (($Max/1024)/1024)
        "Min" = (($Min/1024)/1024)
    }
    return $Data;
}
if ($InputSubscriptionIDList.Count -eq 0) {
    Write-Host ("[$(Get-Date -UFormat $dFormat)] Listando todas as Assinaturas") -ForegroundColor Yellow;
    $SubscriptionIDListTemp = (Get-AzSubscription | Select-Object -Property Id);
    $SubscriptionIDList = @();
    foreach ($Subscription in $SubscriptionIDListTemp) {$SubscriptionIDList += $Subscription.Id};
    Write-Host ("[$(Get-Date -UFormat $dFormat)] $($SubscriptionIDList.Count) Assinaturas encontradas") -ForegroundColor Green;
}
else {
    $SubscriptionIDList = $InputSubscriptionIDList;
}
foreach ($SubscriptionID in $SubscriptionIDList) {
    $CountRGs = 1;
    Write-Host ("[$(Get-Date -UFormat $dFormat)] Selecionando Assinatura $($SubscriptionID)") -ForegroundColor Yellow;
    $SelectedSubscription = (Select-AzSubscription -SubscriptionID $SubscriptionID);
    Write-Information $SelectedSubscription;
    if ($InputResourceGroupNameList.Count -eq 0) {
        Write-Host ("[$(Get-Date -UFormat $dFormat)] Listando todos os Resource Groups da Assinatura $($SubscriptionID)") -ForegroundColor Yellow;
        $ResourceGroupNameListTemp = (Get-AzResourceGroup | Select-Object -Property ResourceGroupName);
        $ResourceGroupNameList = @();
        foreach ($ResourceGroup in $ResourceGroupNameListTemp) {$ResourceGroupNameList += $ResourceGroup.ResourceGroupName};
        Write-Host ("[$(Get-Date -UFormat $dFormat)] $($ResourceGroupNameList.Count) Resource Groups encontrados na Assinatura $($SubscriptionID)") -ForegroundColor Green;
    }
    else {
        $ResourceGroupNameList = $InputResourceGroupNameList;
    }
    foreach ($ResourceGroupName in $ResourceGroupNameList) {
        Write-Host ("[$(Get-Date -UFormat $dFormat)] RG $($CountRGs) de $($ResourceGroupNameList.Count)") -ForegroundColor White;
        $ResourceGroupInfo = (Get-AzResourceGroup -Name $ResourceGroupName -ErrorVariable resourceGroupDoesNotExist -ErrorAction SilentlyContinue);
        Write-Information $ResourceGroupInfo;
        if ($resourceGroupDoesNotExist) {
            Write-Host ("[$(Get-Date -UFormat $dFormat)] Resource Group $($ResourceGroupName) não existe na Assinatura $($SubscriptionID)") -ForegroundColor Red;
            $VMList = @();
        }
        else {
            if ($InputVMList.Count -eq 0) {
                Write-Host ("[$(Get-Date -UFormat $dFormat)] Listando todas as VMs no Resource Group $($ResourceGroupName) da Assinatura $($SubscriptionID)") -ForegroundColor Yellow;
                $VMListTemp = (Get-AzVM -ResourceGroupName $ResourceGroupName | Select-Object -Property Name);
                $VMList = @();
                foreach ($VM in $VMListTemp) {$VMList += $VM.Name};
                Write-Host ("[$(Get-Date -UFormat $dFormat)] $($VMList.Count) VMs encontradas no Resource Group $($ResourceGroupName) da Assinatura $($SubscriptionID)") -ForegroundColor Green;
            }
            else {
                $VMList = $InputVMList;
            }
        }
        $CountVMs = 1;
        foreach ($VMName in $VMList) {
            $LT50 = "False";
            $VMRecommendedSize = "";
            Write-Host ("[$(Get-Date -UFormat $dFormat)] VM $($CountVMs) de $($VMList.Count)") -ForegroundColor Cyan;
            Write-Host ("[$(Get-Date -UFormat $dFormat)] Obtendo informações da VM $($VMName) do Resource Group $($ResourceGroupName) da Assinatura $($SubscriptionID)") -ForegroundColor Yellow;
            $VMInfo = (Get-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName);
            $VMID = $VMInfo.Id;
            $VMLocation = $VMInfo.Location;
            Write-Host ("[$(Get-Date -UFormat $dFormat)] Calculando uso de CPU na VM $($VMName) do Resource Group $($ResourceGroupName) da Assinatura $($SubscriptionID)") -ForegroundColor Yellow;
            $CPUData = (FetchMetricsCPU -ResourceID $VMID -Interval $IntervalInDays -TimeGrain $TimeGrain);
            Write-Host ("[$(Get-Date -UFormat $dFormat)] Calculando uso de Memória na VM $($VMName) do Resource Group $($ResourceGroupName) da Assinatura $($SubscriptionID)") -ForegroundColor Yellow;
            $MemoryData = (FetchMetricsMemory -ResourceID $VMID -Interval $IntervalInDays -TimeGrain $TimeGrain);
            Write-Host ("[$(Get-Date -UFormat $dFormat)] Obtendo informações do size da VM $($VMName)") -ForegroundColor Yellow;
            $VMSizeList = (Get-AzVMSize -Location $VMLocation);
            $VMSizeInfo = $VMSizeList | Where-Object {$_.Name -eq $VMInfo.HardwareProfile.VmSize};
            ############ PENSAR UM POUCO AQUI #############
            $MemoryData.Max = $MemoryData.Min -gt 0 ? $VMSizeInfo.MemoryInMB - $MemoryData.Min : 0;
            $MemoryData.Average = ( ($MemoryData.Average).ToString("#.##") ) ? $VMSizeInfo.MemoryInMB - $MemoryData.Average : 0;
            $MemoryData.Max = $MemoryData.Max -lt 0 ? 0 : $MemoryData.Max;
            ###############################################
            if ( ($CPUData.Max -lt 50) -and ( (($MemoryData.Max/$VMSizeInfo.MemoryInMB) * 100) -lt 50 ) ) {
                $LT50 = "True";
                foreach ($Size in $VMSizeList) {
                    if ( ($Size.NumberOfCores -ge $VMSizeInfo.NumberOfCores/2) -and ($Size.NumberOfCores -lt $VMSizeInfo.NumberOfCores) -and ($Size.MemoryInMB -ge $VMSizeInfo.MemoryInMB/2) -and ($Size.MemoryInMB -lt $VMSizeInfo.MemoryInMB) ) {
                        #Standard_E4as_v4_Promo
                        if ($VMSizeInfo.Name.Split("_")[-1].Trim() -eq "Promo") {
                            if ( ($Size.Name.Split("_").Count -eq $VMSizeInfo.Name.Split("_").Count) `
                            -and ($Size.Name.Split("_")[1][0] -eq $VMSizeInfo.Name.Split("_")[1][0]) `
                            -and ($Size.Name.Split("_")[-2].Trim() -eq $VMSizeInfo.Name.Split("_")[-2].Trim()) ) {
                                if ( ( $Size.Name.Trim() -replace '\d+','' ) -eq ( $VMSizeInfo.Name.Trim() -replace '\d+','' ) ) {
                                    $VMRecommendedSize = $Size.Name;
                                    break;
                                }
                            }
                        }
                        elseif ( ($Size.Name.Split("_").Count -eq $VMSizeInfo.Name.Split("_").Count) -and ($Size.Name.Split("_")[1][0] -eq $VMSizeInfo.Name.Split("_")[1][0]) ) {
                            if ( ($VMSizeInfo.Name.Split("_").Count -eq 4 ) ){
                                if ( ($Size.Name.Split("_")[-1].Trim() -eq $VMSizeInfo.Name.Split("_")[-1].Trim() ) ) {
                                    if ( ($Size.Name.Split("_")[-2].Trim() -eq $VMSizeInfo.Name.Split("_")[-2].Trim() ) ) {
                                        if ( ( $Size.Name.Trim() -replace '\d+','' ) -eq ( $VMSizeInfo.Name.Trim() -replace '\d+','' ) ) {
                                            $VMRecommendedSize = $Size.Name;
                                            break;
                                        }
                                    }
                                }
                            }
                            #Standard_E4as_v4
                            if ( ($VMSizeInfo.Name.Split("_").Count -eq 3 ) ){
                                if ( ($Size.Name.Split("_")[-1].Trim() -eq $VMSizeInfo.Name.Split("_")[-1].Trim() ) ) {
                                    if ( ( $Size.Name.Trim() -replace '\d+','' ) -eq ( $VMSizeInfo.Name.Trim() -replace '\d+','' ) ) {
                                        $VMRecommendedSize = $Size.Name;
                                        break;
                                    }
                                }
                            }
                            #Standard_B2ms
                            if ( ($VMSizeInfo.Name.Split("_").Count -eq 2 ) ){
                                if ( ( $Size.Name.Trim() -replace '\d+','' ) -eq ( $VMSizeInfo.Name.Trim() -replace '\d+','' ) ) {
                                    $VMRecommendedSize = $Size.Name;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            $InfoExport += [psCustomObject]@{
                "Resource Id"           = $VMID
                "Average CPU (%)"       = $($CPUData.Average).ToString("#.##")
                "Maximum CPU (%)"       = ($CPUData.Max).ToString("#.##")
                "Average Memory (MB)"   = ($MemoryData.Average).ToString("#.##")
                "Maximum Memory (MB)"   = ($MemoryData.Max).ToString("#.##")
                "Total Memory(MB)"      = $VMSizeInfo.MemoryInMB
                "Vm Size"               = $VMInfo.HardwareProfile.VmSize
                "Region"                = $VMInfo.Location
                "LT 50%"                = $LT50
                "Vm Recommended Size"   = $VMRecommendedSize
            }
            if ($AddRightSizeTag -and ($LT50 -eq "True")) {
                Write-Host ("[$(Get-Date -UFormat $dFormat)] Adicionado Tag no recurso $($VMID)") -ForegroundColor Yellow;
                $UpdateTag = (Update-AzTag -ResourceId $VMID -Tag $RightSizeTag -Operation Merge -ErrorAction SilentlyContinue -ErrorVariable tagNotApplied);
                Write-Information $UpdateTag;
                if ($tagNotApplied) {
                    Write-Host ("[$(Get-Date -UFormat $dFormat)] Houve um problema ao aplicar a Tag no recurso $($VMID)") -ForegroundColor Red;
                    Write-Host $tagNotApplied;
                }
                else {
                    Write-Host ("[$(Get-Date -UFormat $dFormat)] Tag aplicada com sucesso no recurso $($VMID)") -ForegroundColor Green;
                }
            }
            $CountVMs++;
        }
        $CountRGs++;
    }
}
Write-Host ("[$(Get-Date -UFormat $dFormat)] Exportando arquivo de utilização de CPU e Memória") -ForegroundColor Cyan;
if ($ExportFileType -eq "xlsx") {
    $InfoExport | Export-Excel -Path $FileExport -AutoSize -WarningAction SilentlyContinue;
}
else {
    $InfoExport | Export-Csv -Path $FileExport -NoTypeInformation;
}
Write-Host ("[$(Get-Date -UFormat $dFormat)] $($FileExport)") -ForegroundColor Cyan;