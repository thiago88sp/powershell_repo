<#
.SYNOPSIS
    Script para remover snapshots após um período determinado de retenção
.DESCRIPTION
    O script não necessita de inputs, ele irá buscar todos os snapshots criados pela automação e irá deleta-los conforme a retenção definida

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

.PARAMETER ConnectionType
    Tipo de conexão que será utilizada na Automation Account (Managed Identity ou Run As Account)

.EXAMPLE
    PS C:\> SnapshotRetentionByTags.ps1`
    -ConnectionType Identity

    No exemplo acima, serão removidos todos os snapshots que entrarem nos parâmetros da retenção e a conexão na Automation Account será estabelecida utilizando sua Managed Identity

.NOTES
    Filename: SnapshotRetentionByTags.ps1
    Author: Caio Souza do Carmo
    Modified date: 2022-07-27
    Version 1.0 - Remover snapshots
    Version 1.1 - Ajuste de variação de valor nas Tags
#>
#Requires -Version 7
param(
    [Parameter(Mandatory = $false, HelpMessage = "Connection Type")]
    [ValidateSet("Identity", "RunAs", "Local", IgnoreCase = $true)]
    [String]$ConnectionType = "RunAs"
)

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

$TFile = (StartTranscript -TranscriptName "SnapshotRetentionLogs");

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

$CurrentDate = (Get-Date);
$SnapshotsDeleted = 0;
$SnapshotsKept = 0;
$SnapshotsError = 0;

$DevNames = @("dev", "DEV");
$HmlNames = @("hml", "HML");
$PrdNames = @("prd", "PRD", "prod", "PROD", "PRD]", "pdr", "PDR", "waf", "WAF");

foreach ($Subscription in $SubscriptionList) {
    Write-Host ("[$(GetDate)] Selecionando assinatura $($Subscription.Id)") -ForegroundColor Yellow;
    $SelectedSubscription = (Select-AzSubscription -SubscriptionId $Subscription.Id);
    Write-Host ("[$(GetDate)] Assinatura selecionada: `"$($SelectedSubscription.Subscription.Name)`" ") -ForegroundColor Green;

    Write-Host ("[$(GetDate)] Listando snapshots gerados pela automação") -ForegroundColor Yellow;
    $SnapshotList = (Get-AzSnapshot | Where-Object { ($_.Tags.ContainsKey("managedby")) -and ($_.Tags.ContainsKey("environment")) -and ($_.Tags["managedby"] -eq "automation") });
    Write-Host ("[$(GetDate)] $($SnapshotList.Count) snapshots encontrados") -ForegroundColor Green;

    foreach ($Snapshot in $SnapshotList) {
        $ResourceGroupName = $Snapshot.ResourceGroupName;
        $SnapshotName = $Snapshot.Name;

        Write-Host ("[$(GetDate)] Validando snapshot `"$($SnapshotName)`" ") -ForegroundColor Yellow;

        $RetentionDate = ($Snapshot.TimeCreated).AddYears(99);
        $EnvironmentTag = $Snapshot.Tags["environment"];
        if ($EnvironmentTag -in $DevNames) {
            $RetentionDate = ($Snapshot.TimeCreated).AddDays(15);
        }
        elseif ($EnvironmentTag -in $HmlNames) {
            $RetentionDate = ($Snapshot.TimeCreated).AddDays(15);
        }
        elseif ($EnvironmentTag -in $PrdNames) {
            $RetentionDate = ($Snapshot.TimeCreated).AddDays(30);
        }
        else {
            $RetentionDate = ($Snapshot.TimeCreated).AddYears(99);
        }
    
        if ($CurrentDate -gt $RetentionDate) {
            Write-Host ("[$(GetDate)] Snapshot `"$($Snapshot.Name)`" será deletado pois sua retenção era somente até $($RetentionDate.ToString("yyyy-MM-dd HH:mm:ss")) ") -ForegroundColor Yellow;

            Remove-AzSnapshot -ResourceGroupName $ResourceGroupName `
                -SnapshotName $SnapshotName `
                -ErrorVariable SnapshotNotDeleted `
                -ErrorAction SilentlyContinue `
                -Force | Out-Null;
            if (!$SnapshotNotDeleted) {
                Write-Host ("[$(GetDate)] Snapshot `"$($SnapshotName)`" deletado com sucesso") -ForegroundColor Green;
                $SnapshotsDeleted++;
            }
            else {
                Write-Host ("[$(GetDate)] Não foi possível deletar o snapshot `"$($SnapshotName)`"") -ForegroundColor Red;
                Write-Host ($SnapshotNotDeleted) -ForegroundColor Red;
                $SnapshotsError++;
            }
        }
        else {
            Write-Host ("[$(GetDate)] Snapshot `"$($Snapshot.Name)`" será deletado somente após $($RetentionDate.ToString("yyyy-MM-dd HH:mm:ss")) ") -ForegroundColor Green;
            $SnapshotsKept++;
        }
    }
}

Write-Host ("[$(GetDate)] Snapshots deletados: $($SnapshotsDeleted)") -ForegroundColor Cyan;
Write-Host ("[$(GetDate)] Snapshots mantidos: $($SnapshotsKept)") -ForegroundColor Cyan;
Write-Host ("[$(GetDate)] Snapshots com erro ao deletar: $($SnapshotsError)") -ForegroundColor Cyan;

Stop-Transcript;