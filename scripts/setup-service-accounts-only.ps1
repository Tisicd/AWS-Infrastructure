# =============================================================================
# Script de Despliegue Solo Service Accounts - QA Environment
# =============================================================================
# Este script despliega SOLO las service accounts (no toca el hub account)
# Detecta automaticamente: Account ID, VPC y Subnets para cada service account
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "qa", "prod")]
    [string]$Environment = "qa",
    
    [Parameter(Mandatory=$false)]
    [int]$ServiceAccountCount = 4
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Despliegue Solo Service Accounts" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Service Accounts a desplegar: $ServiceAccountCount" -ForegroundColor Yellow
Write-Host ""

# Verificar herramientas
Write-Host "Verificando herramientas..." -ForegroundColor Yellow
$toolsOk = $true

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Terraform no encontrado" -ForegroundColor Red
    $toolsOk = $false
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] AWS CLI no encontrado" -ForegroundColor Red
    $toolsOk = $false
}

if (-not $toolsOk) {
    exit 1
}

Write-Host "[OK] Herramientas verificadas" -ForegroundColor Green

# Directorio de trabajo
$terraformRoot = (Get-Location).Path
if (-not (Test-Path "main.tf")) {
    Write-Host "[ERROR] Este script debe ejecutarse desde el directorio raiz de Terraform" -ForegroundColor Red
    exit 1
}

# =============================================================================
# Obtener informacion del Hub Account
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "OBTENIENDO INFORMACION DEL HUB ACCOUNT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Verificar que existe el archivo de outputs del hub
$hubOutputsPath = Join-Path $terraformRoot "deployments\hub-account\hub-outputs.json"
if (-not (Test-Path $hubOutputsPath)) {
    Write-Host "[ERROR] No se encontraron outputs del Hub Account" -ForegroundColor Red
    Write-Host "Asegurate de haber desplegado el Hub Account primero" -ForegroundColor Yellow
    exit 1
}

Write-Host "`nLeyendo outputs del Hub Account..." -ForegroundColor Yellow
try {
    $hubOutputs = Get-Content $hubOutputsPath | ConvertFrom-Json
    
    $HubAccountId = if ($hubOutputs.current_account_id.value) { $hubOutputs.current_account_id.value } else { $null }
    $HubVpcCidr = if ($hubOutputs.vpc_cidr_block.value) { $hubOutputs.vpc_cidr_block.value } else { $null }
    $HubDatabaseIp = if ($hubOutputs.database_private_ip.value) { $hubOutputs.database_private_ip.value } else { $null }
    $HubKongEndpoint = if ($hubOutputs.kong_proxy_endpoint.value) { $hubOutputs.kong_proxy_endpoint.value } else { $null }
    
    # Validar valores requeridos
    if ([string]::IsNullOrWhiteSpace($HubAccountId)) {
        Write-Host "[ERROR] Hub Account ID no encontrado en outputs" -ForegroundColor Red
        exit 1
    }
    
    if ([string]::IsNullOrWhiteSpace($HubVpcCidr)) {
        Write-Host "[ERROR] Hub VPC CIDR no encontrado en outputs" -ForegroundColor Red
        exit 1
    }
    
    if ([string]::IsNullOrWhiteSpace($HubDatabaseIp) -or $HubDatabaseIp -eq "null") {
        Write-Host "[ADVERTENCIA] Hub Database IP no disponible en outputs" -ForegroundColor Yellow
        Write-Host "Puede ser porque la base de datos usa ASG y la IP aun no esta disponible" -ForegroundColor Yellow
        Write-Host "Ingresa manualmente la IP privada de la base de datos del Hub Account:" -ForegroundColor Yellow
        $HubDatabaseIp = Read-Host "Database IP"
        
        if ([string]::IsNullOrWhiteSpace($HubDatabaseIp)) {
            Write-Host "[ERROR] Database IP es requerida" -ForegroundColor Red
            exit 1
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($HubKongEndpoint) -or $HubKongEndpoint -eq "null") {
        Write-Host "[ADVERTENCIA] Hub Kong Endpoint no disponible en outputs" -ForegroundColor Yellow
        Write-Host "Ingresa manualmente el endpoint de Kong del Hub Account:" -ForegroundColor Yellow
        $HubKongEndpoint = Read-Host "Kong Endpoint (ej: http://IP:8000)"
        
        if ([string]::IsNullOrWhiteSpace($HubKongEndpoint)) {
            Write-Host "[ERROR] Kong Endpoint es requerido" -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "[OK] Hub Account ID: $HubAccountId" -ForegroundColor Green
    Write-Host "[OK] Hub VPC CIDR: $HubVpcCidr" -ForegroundColor Green
    Write-Host "[OK] Hub Database IP: $HubDatabaseIp" -ForegroundColor Green
    Write-Host "[OK] Hub Kong Endpoint: $HubKongEndpoint" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Error al leer outputs del Hub Account" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# =============================================================================
# Limpiar estado de Terraform antes de comenzar
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "LIMPIEZA DE ESTADO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Limpiando estado de Terraform para evitar conflictos..." -ForegroundColor Yellow

if (Test-Path "terraform.tfstate") {
    Remove-Item "terraform.tfstate" -Force
    Write-Host "[OK] Estado principal eliminado" -ForegroundColor Green
}

if (Test-Path "terraform.tfstate.backup") {
    Remove-Item "terraform.tfstate.backup" -Force
    Write-Host "[OK] Backup eliminado" -ForegroundColor Green
}

# =============================================================================
# Desplegar Service Accounts
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DESPLEGANDO SERVICE ACCOUNTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$serviceAccounts = @()
$serviceVpcCidrs = @()

for ($i = 1; $i -le $ServiceAccountCount; $i++) {
    Write-Host "`n----------------------------------------" -ForegroundColor Cyan
    $accountNumStr = $i.ToString()
    $headerMsg = "Service Account " + $accountNumStr + " de " + $ServiceAccountCount.ToString()
    Write-Host $headerMsg -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    
    $importantMsg = "[IMPORTANTE] Configura las credenciales AWS para la Service Account " + $accountNumStr
    Write-Host "`n$importantMsg" -ForegroundColor Yellow
    Write-Host "Presiona Enter cuando estes listo..." -ForegroundColor Yellow
    Read-Host
    
    # Verificar credenciales Service Account
    Write-Host "`nVerificando credenciales AWS..." -ForegroundColor Yellow
    try {
        $serviceIdentity = aws sts get-caller-identity 2>&1 | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            throw "AWS CLI error"
        }
        
        $serviceAccountId = $serviceIdentity.Account
        $okMsg = "[OK] Service Account " + $accountNumStr + " ID: " + $serviceAccountId
        Write-Host $okMsg -ForegroundColor Green
        $arnMsg = "  User ARN: " + $serviceIdentity.Arn
        Write-Host $arnMsg -ForegroundColor Cyan
        
        if ($serviceAccountId -eq $HubAccountId) {
            Write-Host '[ADVERTENCIA] Esta es la misma cuenta que el Hub!' -ForegroundColor Yellow
            $confirm = Read-Host 'Continuar de todas formas? (S/N)'
            if ($confirm -ne 'S' -and $confirm -ne 's') {
                $skipMsg = "[INFO] Saltando Service Account " + $accountNumStr
                Write-Host $skipMsg -ForegroundColor Yellow
                continue
            }
        }
    } catch {
        $errorMsg = "[ERROR] No se pueden obtener credenciales AWS para Service Account " + $accountNumStr
        Write-Host $errorMsg -ForegroundColor Red
        $infoMsg = "[INFO] Saltando Service Account " + $accountNumStr
        Write-Host $infoMsg -ForegroundColor Yellow
        continue
    }
    
    # Limpiar estado antes de cada despliegue
    Write-Host "`nLimpiando estado de Terraform..." -ForegroundColor Yellow
    if (Test-Path "terraform.tfstate") {
        Remove-Item "terraform.tfstate" -Force
    }
    if (Test-Path "terraform.tfstate.backup") {
        Remove-Item "terraform.tfstate.backup" -Force
    }
    
    # Ejecutar script de service account (que detecta automaticamente VPC y subnets)
    $serviceScript = Join-Path $terraformRoot "scripts\setup-service-account.ps1"
    if (Test-Path $serviceScript) {
        $execMsg = "`nEjecutando script de Service Account " + $accountNumStr + "..."
        Write-Host $execMsg -ForegroundColor Yellow
        Write-Host "El script detectara automaticamente:" -ForegroundColor Cyan
        $accountIdMsg = "  - Account ID: " + $serviceAccountId
        Write-Host $accountIdMsg -ForegroundColor Gray
        Write-Host "  - VPC (seleccion interactiva)" -ForegroundColor Gray
        Write-Host "  - Subnets (seleccion interactiva)" -ForegroundColor Gray
        
        & $serviceScript `
            -Environment $Environment `
            -HubAccountId $HubAccountId `
            -HubVpcCidr $HubVpcCidr `
            -HubDatabaseIp $HubDatabaseIp `
            -HubKongEndpoint $HubKongEndpoint `
            -AccountNumber $i
        
        if ($LASTEXITCODE -ne 0) {
            $deployErrorMsg = "[ERROR] Error al desplegar Service Account " + $accountNumStr
            Write-Host $deployErrorMsg -ForegroundColor Red
            Write-Host "[INFO] Continuando con la siguiente service account..." -ForegroundColor Yellow
            continue
        }
        
        # Obtener VPC CIDR de esta service account
        $serviceOutputsPath = Join-Path $terraformRoot "deployments\service-account-$i\service-outputs.json"
        if (Test-Path $serviceOutputsPath) {
            try {
                $serviceOutputs = Get-Content $serviceOutputsPath | ConvertFrom-Json
                $serviceVpcCidr = $serviceOutputs.vpc_cidr_block.value
                $serviceVpcCidrs += $serviceVpcCidr
                $serviceAccounts += @{
                    AccountId = $serviceAccountId
                    VpcCidr = $serviceVpcCidr
                    Number = $i
                }
                
                $vpcCidrMsg = "[OK] Service Account " + $accountNumStr + " VPC CIDR: " + $serviceVpcCidr
                Write-Host $vpcCidrMsg -ForegroundColor Green
            } catch {
                $readErrorMsg = "[ADVERTENCIA] No se pudo leer el VPC CIDR de Service Account " + $accountNumStr
                Write-Host $readErrorMsg -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "[ERROR] Script de Service Account no encontrado: $serviceScript" -ForegroundColor Red
        Write-Host "[INFO] Continuando con la siguiente service account..." -ForegroundColor Yellow
        continue
    }
}

# =============================================================================
# RESUMEN
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESUMEN DEL DESPLIEGUE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor White
Write-Host "Hub Account ID: $HubAccountId" -ForegroundColor White
Write-Host "Hub VPC CIDR: $HubVpcCidr" -ForegroundColor White
$summaryMsg = "`nService Accounts desplegados: " + $serviceAccounts.Count.ToString() + " de " + $ServiceAccountCount.ToString()
Write-Host $summaryMsg -ForegroundColor White

if ($serviceAccounts.Count -gt 0) {
    foreach ($account in $serviceAccounts) {
        $accountNum = $account.Number.ToString()
        $accountInfo = "  Service Account " + $accountNum + ": " + $account.AccountId + " (VPC: " + $account.VpcCidr + ")"
        Write-Host $accountInfo -ForegroundColor Cyan
    }
} else {
    Write-Host "  [ADVERTENCIA] No se desplego ninguna service account" -ForegroundColor Yellow
}

Write-Host "`n[OK] Proceso completado" -ForegroundColor Green

if ($serviceAccounts.Count -gt 0) {
    Write-Host "`nNOTA: Si necesitas actualizar el Hub Account con los CIDRs de las Service Accounts," -ForegroundColor Yellow
    Write-Host "ejecuta el script de actualizacion del hub manualmente:" -ForegroundColor Yellow
    $cidrsString = $serviceVpcCidrs -join ','
    $updateCommand = '.\scripts\update-hub-with-service-cidr.ps1 -ServiceVpcCidrs "' + $cidrsString + '" -Environment ' + $Environment
    $commandLine = "  " + $updateCommand
    Write-Host $commandLine -ForegroundColor Cyan
}
