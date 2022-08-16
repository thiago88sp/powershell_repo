<#
.SYNOPSIS
    Script para realizar snapshot de todas as VMs que contenham Tags especificas
.DESCRIPTION
    O script não necessita de inputs, ele irá buscar todas as VMs no ambiente com as Tags especificas no código

    Para iniciar, é necessário ter instalado o módulo Az
        Install-Module -Name Az
    
    É necessário estar conectado à conta do Azure em que a(s) sua(s) Assinatura(s) existe(m)
    Se executado no Cloud Shell, os comandos abaixo não são necessários
        Para conectar, utilize o comando abaixo:
        Connect-AzAccount 

        Caso você possua mais de um diretório na mesma conta, pode ser especificado o TenantID em que as Assinaturas escolhidas existem
        Connect-AzAccount -TenantId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

        Caso a página de login não abra automaticamente, pode ser utilizado o comando abaixo para gerar um código que deve ser inserido na URL "https://microsoft.com/devicelogin" para possibilitar o login
            Connect-AzAccount -UseDeviceAuthentication

.PARAMETER Suffix
    Sufixo que será adicionado ao nome do disco para formar o nome do snapshot
    
.PARAMETER TargetResourceGroup
    Grupo de recursos em que os snapshots serão criados

.PARAMETER ConnectionType
    Tipo de conexão que será utilizada na Automation Account (Managed Identity ou Run As Account)

.EXAMPLE
    PS C:\> SnapshotByVMTags.ps1
    -Suffix backup

    No exemplo acima, será feito o snapshot de todas as VMs com as Tags definidas e o nome do snapshot será composto por "<Nome do disco>-backup"

.EXAMPLE
    PS C:\> SnapshotByVMTags.ps1`
    -ConnectionType Identity

    No exemplo acima, será feito o snapshot de todas as VMs com as Tags definidas e a conexão na Automation Account será estabelecida utilizando sua Managed Identity

.EXAMPLE
    PS C:\> SnapshotByVMTags.ps1`
    -TargetResourceGroup backup

    No exemplo acima, será feito o snapshot de todas as VMs com as Tags definidas e todos os snapshots serão salvos no Resource Group "backup"

.NOTES
    Filename: SnapshotByVMTags.ps1
    Author: Caio Souza do Carmo
    Modified date: 2022-07-26
    Version 1.0 - Atualizar snapshot existente
#>
#Requires -Version 7
param(
    [Parameter(Mandatory = $false, HelpMessage = "Suffix for Snapshot Name")]
    [String]$Suffix = "snap-$(Get-Date -UFormat "%Y%m%d")",

    [Parameter(Mandatory = $false, HelpMessage = "Target Resource Group")]
    [String]$TargetResourceGroup = "RSG_COETECH_SNAPSHOTS",

    [Parameter(Mandatory = $false, HelpMessage = "Connection Type")]
    [ValidateSet("Identity", "RunAs", "Local", IgnoreCase = $true)]
    [String]$ConnectionType = "RunAs"
)

$SnapshotsCreated = 0;
$SnapshotsNotCreated = 0;
$SnapshotsUpdated = 0;
$SnapshotsNotUpdated = 0;

function GetDate() {
    $tDate = (Get-Date).ToUniversalTime();
    $TimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("E. South America Standard Time");
    $tCurrentTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($tDate, $TimeZone);
    
    $DateInfo = @{
        "UFormat" = "%Y-%m-%d %H:%M:%S"
        "Date"    = $tCurrentTime
    }

    return Get-Date @DateInfo;
}

function StartTranscript {
    param(
        [Parameter()]
        [String]$TranscriptName
    )

    $DateTime = Get-Date -UFormat "%Y-%m-%d-%H-%M-%S";
    $CurrentDir = $(Get-Location).Path;
    $TFile = (Join-Path -Path $CurrentDir -ChildPath "$($TranscriptName)-$($DateTime).txt")
	(Start-Transcript -Path $TFile -Append -NoClobber | Out-Null);
    return $TFile;
}

function UploadTranscript {
    param (
        [Parameter()]
        [String]$TFile,

        [Parameter()]
        [String]$StorageAccountId,

        [Parameter()]
        [String]$ContainerName
    )
    
    $FileName = (Split-Path $TFile -Leaf);
    $TempID = $StorageAccountId.Split("/");
    $SubscriptionId = $TempId[2];
    $ResourceGroupName = $TempID[4];
    $StorageName = $TempID[-1];

    Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null;
    $StorageAccount = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageName);

    Set-AzStorageBlobContent -File $TFile `
        -Container $ContainerName `
        -Blob $FileName `
        -Context $StorageAccount.Context `
        -StandardBlobTier Hot `
        -ErrorVariable FileNotSent `
        -Force | Out-Null;

    if (!$FileNotSent) {
        Write-Host ("[$(GetDate)] Transcript enviado para a Storage Account `"$($StorageName)`"") -ForegroundColor Green;
    }
    else {
        Write-Host ($FileNotSent);
        Write-Host ("[$(GetDate)] Não foi possível enviar o Transcript para a Storage Account `"$($StorageName)`"") -ForegroundColor Red;
    } 
}

$TFile = (StartTranscript -TranscriptName "SnapshotLogs");

if (@("Identity", "RunAs") -contains $ConnectionType) {
    Import-Module Az;
    if ($ConnectionType -eq "Identity") {
        Write-Host ("[$(GetDate)] Conectando ao Azure") -ForegroundColor Yellow;
        Connect-AzAccount -Identity -ErrorAction Stop -ErrorVariable AccountNotConnected;
        if ($AccountNotConnected) {
            Write-Host ("[$(GetDate)] Falha ao conectar ao Azure") -ForegroundColor Red;
        }
        else {
            Write-Host ("[$(GetDate)] Conexão realizada com sucesso") -ForegroundColor Green;
        }
    }
    elseif ($ConnectionType -eq "RunAs") {
        Write-Host ("[$(GetDate)] Obtendo conexão da Automation Account") -ForegroundColor Yellow;
        $ServicePrincipalConnection = (Get-AutomationConnection -Name "AzureRunAsConnection");
    
        $AzAccountParams = @{
            "ServicePrincipal"      = $True
            "Tenant"                = $ServicePrincipalConnection.TenantID
            "ApplicationId"         = $ServicePrincipalConnection.ApplicationID
            "CertificateThumbprint" = $ServicePrincipalConnection.CertificateThumbprint
            "ErrorAction"           = "Stop"
            "ErrorVariable"         = "AccountNotConnected"
        }
        Write-Host ("[$(GetDate)] Tenant Id: $($ServicePrincipalConnection.TenantID)") -ForegroundColor Cyan;
    
        Write-Host ("[$(GetDate)] Conectando ao Azure") -ForegroundColor Yellow;
        (Connect-AzAccount @AzAccountParams);
    
        if ($AccountNotConnected) {
            Write-Host ("[$(GetDate)] Falha ao conectar ao Azure") -ForegroundColor Red;
        }
        else {
            Write-Host ("[$(GetDate)] Conexão realizada com sucesso") -ForegroundColor Green;
        }
    }
    else {
        Exit;
    }
}

Write-Host ("[$(GetDate)] Listando assinaturas") -ForegroundColor Yellow;
$SubscriptionList = (Get-AzSubscription);
Write-Host ("[$(GetDate)] $($SubscriptionList.Count) assinaturas encontradas") -ForegroundColor Green;

foreach ($Subscription in $SubscriptionList) {
    Write-Host ("[$(GetDate)] Selecionando assinatura $($Subscription.Id)") -ForegroundColor Yellow;
    $SelectedSubscription = (Select-AzSubscription -SubscriptionId $Subscription.Id);
    Write-Host ("[$(GetDate)] Assinatura selecionada: `"$($SelectedSubscription.Subscription.Name)`" ") -ForegroundColor Green;

    Write-Host ("[$(GetDate)] Listando VMs para realizar o(s) snapshot(s)") -ForegroundColor Yellow;
    $VMList = (Get-AzVM | Where-Object { ($_.Tags.ContainsKey("environment")) -and ($_.Tags.ContainsKey("snapshot")) -and ($_.Tags["snapshot"] -eq "true") } );
    Write-Host ("[$(GetDate)] $($VMList.Count) VM(s) encontrada(s)") -ForegroundColor Green;
    foreach ($VM in $VMList) {
        $VMID = $VM.Id;

        $TempID = $VMID.Split("/");
        $ResourceGroupName = $TempID[4];
        $VMName = $TempID[-1];

        $TargetResourceGroup = $TargetResourceGroup ? $TargetResourceGroup : $ResourceGroupName;
        
        $Location = $VM.Location;
        
        $DataDiskList = @();
        $TotalDisks = 1;
        $SnapshotTags = @{
            "environment" = $VM.Tags["environment"]
            "managedby"   = "automation"
        }

        Write-Host ("[$(GetDate)] VM atual: `"$($VMName)`" ") -ForegroundColor Green;

        $OSDiskName = $VM.StorageProfile.OsDisk.Name;
        Write-Host ("[$(GetDate)] Nome do disco de S.O: `"$($OSDiskName)`"") -ForegroundColor Yellow;

        if (!($VM.StorageProfile.OsDisk.ManagedDisk  | ConvertTo-Json | ConvertFrom-Json -AsHashtable).ContainsKey("Id")) {
            Write-Host ("[$(GetDate)] O disco `"$($OSDiskName)`" não é gerenciado, portanto não será possível realizar o snapshot") -ForegroundColor Yellow;
        }
        else {
            $DataDiskList += $VM.StorageProfile.OsDisk.ManagedDisk.Id;
        }

        $DataDiskListTemp = $VM.StorageProfile.DataDisks;
        
        Write-Host ("[$(GetDate)] $($DataDiskListTemp.Count) discos de dados encontrados") -ForegroundColor Yellow;
        foreach ($DataDisk in $DataDiskListTemp) {
            Write-Host ("[$(GetDate)] Nome do disco de dados: $($DataDisk.Name)") -ForegroundColor Yellow;

            if (!($DataDisk.ManagedDisk | ConvertTo-Json | ConvertFrom-Json -AsHashtable).ContainsKey("Id")) {
                Write-Host ("[$(GetDate)] O disco `"$($DataDisk.Name)`" não é gerenciado, portanto não será possível realizar o snapshot") -ForegroundColor Yellow;
            }
            else {
                $DataDiskList += $DataDisk.ManagedDisk.Id;
            }
            $TotalDisks++;
        }

        Write-Host ("[$(GetDate)] Será realizado o snapshot de $($DataDiskList.Length) discos de um total de $($TotalDisks)") -ForegroundColor Cyan;
        Write-Host ("[$(GetDate)] Iniciando snapshot dos $($DataDiskList.Length) discos") -ForegroundColor Yellow;
        foreach ($DiskID in $DataDiskList) {
            $DiskName = $DiskID.Split("/")[-1];
            $SnapshotName = "$($DiskName)-$($Suffix)";
            $SnapshotConfigParams = @{
                "SourceUri"    = $DiskID
                "AccountType"  = "Standard_LRS"
                "Location"     = $Location
                "Tag"          = $SnapshotTags
                "CreateOption" = "Copy"
            }
            $SnapshotConfig = (New-AzSnapshotConfig @SnapshotConfigParams);

            Write-Host ("[$(GetDate)] Verificando se o snapshot `"$($SnapshotName)`" já existe") -ForegroundColor Yellow;
            (Get-AzSnapshot -ResourceGroupName $TargetResourceGroup `
                -SnapshotName $SnapshotName `
                -ErrorAction SilentlyContinue `
                -ErrorVariable FullSnapshot | Out-Null);
            if ($FullSnapshot) {
                Write-Host ("[$(GetDate)] Snapshot `"$($SnapshotName)`" não existe, será criado") -ForegroundColor Yellow;
                $SnapshotInfo = (New-AzSnapshot -ResourceGroupName $TargetResourceGroup `
                        -SnapshotName $SnapshotName `
                        -Snapshot $SnapshotConfig `
                        -ErrorVariable SnapshotNotCreated `
                        -ErrorAction SilentlyContinue);
                if (!$SnapshotNotCreated) {
                    Write-Host ("[$(GetDate)] Snapshot do disco `"$($DiskName)`" criado com sucesso") -ForegroundColor Green;
                    Write-Host ("[$(GetDate)] ID do Snapshot: `"$($SnapshotInfo.Id)`"") -ForegroundColor Yellow;
                    $SnapshotsCreated++;
                }
                else {
                    Write-Host ("[$(GetDate)] Não foi possível criar o snapshot do disco `"$($DiskName)`"") -ForegroundColor Red;
                    Write-Host ($SnapshotNotCreated) -ForegroundColor Red;
                    $SnapshotsNotCreated++;
                }
            }
            else {
                Write-Host ("[$(GetDate)] Snapshot `"$($SnapshotName)`" já existe, será atualizado") -ForegroundColor Yellow;
                $SnapshotInfo = (Update-AzSnapshot -ResourceGroupName $TargetResourceGroup `
                        -SnapshotName $SnapshotName `
                        -Snapshot $SnapshotConfig `
                        -ErrorVariable SnapshotNotUpdated `
                        -ErrorAction SilentlyContinue);
                if (!$SnapshotNotUpdated) {
                    Write-Host ("[$(GetDate)] Snapshot do disco `"$($DiskName)`" atualizado com sucesso") -ForegroundColor Green;
                    Write-Host ("[$(GetDate)] ID do Snapshot: `"$($SnapshotInfo.Id)`"") -ForegroundColor Yellow;
                    $SnapshotsUpdated++;
                }
                else {
                    Write-Host ("[$(GetDate)] Não foi possível atualizar o snapshot do disco `"$($DiskName)`"") -ForegroundColor Red;
                    Write-Host ($SnapshotNotUpdated) -ForegroundColor Red;
                    $SnapshotsNotUpdated++
                }
            }
        }
    }
}

Write-Host ("[$(GetDate)] Snapshots criados: $($SnapshotsCreated)") -ForegroundColor Cyan;
Write-Host ("[$(GetDate)] Snapshots não criados: $($SnapshotsNotCreated)") -ForegroundColor Cyan;
Write-Host ("[$(GetDate)] Snapshots atualizados: $($SnapshotsUpdated)") -ForegroundColor Cyan;
Write-Host ("[$(GetDate)] Snapshots não atualizados: $($SnapshotsNotUpdated)") -ForegroundColor Cyan;

Stop-Transcript;

<# UploadTranscript -TFile $TFile `
    -StorageAccountId "/subscriptions/0b397135-7b70-4011-9f2b-ac562fb77959/resourceGroups/RSG_COETECH_SNAPSHOTS/providers/Microsoft.Storage/storageAccounts/coetechtranscript" `
    -ContainerName "transcripts"; #>