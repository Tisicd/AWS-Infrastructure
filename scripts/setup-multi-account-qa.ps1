# =============================================================================
# Script de Despliegue Multi-Cuenta - QA Environment
# =============================================================================
# Este script despliega la infraestructura en 5 cuentas AWS:
# - 1 cuenta Hub (recursos compartidos)
# - 4 cuentas Service (microservicios)
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
Write-Host "Despliegue Multi-Cuenta - QA Environment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Cuentas a desplegar:" -ForegroundColor Yellow
Write-Host "  - 1 Hub Account" -ForegroundColor White
Write-Host "  - $ServiceAccountCount Service Accounts" -ForegroundColor White
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
    Write-Host "[ERROR] Este script debe ejecutarse desde el directorio raíz de Terraform" -ForegroundColor Red
    exit 1
}

# =============================================================================
# PASO 1: Desplegar Hub Account
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PASO 1: Desplegando Hub Account" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n[IMPORTANTE] Asegúrate de haber configurado las credenciales AWS para la cuenta Hub" -ForegroundColor Yellow
Write-Host "Presiona Enter cuando estés listo para continuar..." -ForegroundColor Yellow
Read-Host

# Verificar credenciales Hub
$hubIdentity = aws sts get-caller-identity 2>&1 | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] No se pueden obtener credenciales AWS para Hub Account" -ForegroundColor Red
    exit 1
}

$hubAccountId = $hubIdentity.Account
Write-Host "[OK] Hub Account ID: $hubAccountId" -ForegroundColor Green

# Ejecutar script de hub account con environment
$hubScript = Join-Path $terraformRoot "scripts\setup-hub-account.ps1"
if (Test-Path $hubScript) {
    Write-Host "`nEjecutando script de Hub Account..." -ForegroundColor Yellow
    & $hubScript -Environment $Environment
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Error al desplegar Hub Account" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[ERROR] Script de Hub Account no encontrado: $hubScript" -ForegroundColor Red
    exit 1
}

# Obtener outputs del hub
Write-Host "`nObteniendo outputs del Hub Account..." -ForegroundColor Yellow
$hubOutputsPath = Join-Path $terraformRoot "deployments\hub-account\hub-outputs.json"
if (Test-Path $hubOutputsPath) {
    try {
        $hubOutputs = Get-Content $hubOutputsPath | ConvertFrom-Json
        
        $hubVpcCidr = if ($hubOutputs.vpc_cidr_block.value) { $hubOutputs.vpc_cidr_block.value } else { $null }
        $hubDatabaseIp = if ($hubOutputs.database_private_ip.value) { $hubOutputs.database_private_ip.value } else { $null }
        $hubKongEndpoint = if ($hubOutputs.kong_proxy_endpoint.value) { $hubOutputs.kong_proxy_endpoint.value } else { $null }
        
        # Validar valores requeridos
        if ([string]::IsNullOrWhiteSpace($hubVpcCidr) -or $hubVpcCidr -eq "null") {
            Write-Host "[ERROR] Hub VPC CIDR no encontrado en outputs" -ForegroundColor Red
            exit 1
        }
        
        if ([string]::IsNullOrWhiteSpace($hubDatabaseIp) -or $hubDatabaseIp -eq "null") {
            Write-Host "[ADVERTENCIA] Hub Database IP no disponible en outputs (puede ser porque usa ASG)" -ForegroundColor Yellow
            Write-Host "Intentando obtener la IP desde AWS..." -ForegroundColor Yellow
            try {
                # Intentar obtener la IP desde las instancias EC2 o el ASG
                $dbInstances = aws ec2 describe-instances --filters "Name=tag:Name,Values=academic-platform-qa-database*" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].PrivateIpAddress" --output text 2>&1
                if ($LASTEXITCODE -eq 0 -and $dbInstances -and $dbInstances.Trim() -ne "") {
                    $hubDatabaseIp = ($dbInstances -split "`n" | Where-Object { $_ -ne "" } | Select-Object -First 1).Trim()
                    Write-Host "[OK] Database IP obtenida desde AWS: $hubDatabaseIp" -ForegroundColor Green
                } else {
                    Write-Host "Ingresa manualmente la IP privada de la base de datos del Hub Account:" -ForegroundColor Yellow
                    $hubDatabaseIp = Read-Host "Database IP"
                    if ([string]::IsNullOrWhiteSpace($hubDatabaseIp)) {
                        Write-Host "[ERROR] Database IP es requerida" -ForegroundColor Red
                        exit 1
                    }
                }
            } catch {
                Write-Host "Ingresa manualmente la IP privada de la base de datos del Hub Account:" -ForegroundColor Yellow
                $hubDatabaseIp = Read-Host "Database IP"
                if ([string]::IsNullOrWhiteSpace($hubDatabaseIp)) {
                    Write-Host "[ERROR] Database IP es requerida" -ForegroundColor Red
                    exit 1
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($hubKongEndpoint) -or $hubKongEndpoint -eq "null") {
            Write-Host "[ADVERTENCIA] Hub Kong Endpoint no disponible en outputs" -ForegroundColor Yellow
            Write-Host "Ingresa manualmente el endpoint de Kong del Hub Account:" -ForegroundColor Yellow
            $hubKongEndpoint = Read-Host "Kong Endpoint (ej: http://IP:8000 o http://ALB-DNS)"
            if ([string]::IsNullOrWhiteSpace($hubKongEndpoint)) {
                Write-Host "[ERROR] Kong Endpoint es requerido" -ForegroundColor Red
                exit 1
            }
        }
        
        Write-Host "[OK] Hub VPC CIDR: $hubVpcCidr" -ForegroundColor Green
        Write-Host "[OK] Hub Database IP: $hubDatabaseIp" -ForegroundColor Green
        Write-Host "[OK] Hub Kong Endpoint: $hubKongEndpoint" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Error al leer outputs del Hub Account" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[ERROR] No se encontraron outputs del Hub Account" -ForegroundColor Red
    Write-Host "Asegurate de haber desplegado el Hub Account primero" -ForegroundColor Yellow
    exit 1
}

# =============================================================================
# PASO 2: Desplegar Service Accounts
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PASO 2: Desplegando Service Accounts" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$serviceAccounts = @()
$serviceVpcCidrs = @()

for ($i = 1; $i -le $ServiceAccountCount; $i++) {
    Write-Host "`n----------------------------------------" -ForegroundColor Cyan
    Write-Host "Service Account $i de $ServiceAccountCount" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    
    Write-Host "`n[IMPORTANTE] Configura las credenciales AWS para la Service Account $i" -ForegroundColor Yellow
    Write-Host "Presiona Enter cuando estés listo..." -ForegroundColor Yellow
    Read-Host
    
    # Verificar credenciales Service Account
    $serviceIdentity = aws sts get-caller-identity 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] No se pueden obtener credenciales AWS para Service Account $i" -ForegroundColor Red
        continue
    }
    
    $serviceAccountId = $serviceIdentity.Account
    Write-Host "[OK] Service Account $i ID: $serviceAccountId" -ForegroundColor Green
    
    if ($serviceAccountId -eq $hubAccountId) {
        Write-Host "[ADVERTENCIA] Esta es la misma cuenta que el Hub!" -ForegroundColor Yellow
        $confirm = Read-Host "¿Continuar de todas formas? (S/N)"
        if ($confirm -ne "S" -and $confirm -ne "s") {
            continue
        }
    }
    
    # Ejecutar script de service account
    $serviceScript = Join-Path $terraformRoot "scripts\setup-service-account.ps1"
    if (Test-Path $serviceScript) {
        Write-Host "`nEjecutando script de Service Account $i..." -ForegroundColor Yellow
        & $serviceScript `
            -Environment $Environment `
            -HubAccountId $hubAccountId `
            -HubVpcCidr $hubVpcCidr `
            -HubDatabaseIp $hubDatabaseIp `
            -HubKongEndpoint $hubKongEndpoint `
            -AccountNumber $i
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Error al desplegar Service Account $i" -ForegroundColor Red
            continue
        }
        
        # Obtener VPC CIDR de esta service account
        $serviceOutputsPath = Join-Path $terraformRoot "deployments\service-account-$i\service-outputs.json"
        if (Test-Path $serviceOutputsPath) {
            $serviceOutputs = Get-Content $serviceOutputsPath | ConvertFrom-Json
            $serviceVpcCidr = $serviceOutputs.vpc_cidr_block.value
            $serviceVpcCidrs += $serviceVpcCidr
            $serviceAccounts += @{
                AccountId = $serviceAccountId
                VpcCidr = $serviceVpcCidr
                Number = $i
            }
            
            Write-Host "[OK] Service Account $i VPC CIDR: $serviceVpcCidr" -ForegroundColor Green
        }
    } else {
        Write-Host "[ERROR] Script de Service Account no encontrado: $serviceScript" -ForegroundColor Red
        continue
    }
}

# =============================================================================
# PASO 3: Actualizar Hub Account con CIDRs de Service Accounts
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PASO 3: Actualizando Hub Account" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($serviceVpcCidrs.Count -gt 0) {
    Write-Host "`n[IMPORTANTE] Configura las credenciales AWS para el Hub Account nuevamente" -ForegroundColor Yellow
    Write-Host "Presiona Enter cuando estés listo..." -ForegroundColor Yellow
    Read-Host
    
    Write-Host "`nActualizando Hub Account con CIDRs de Service Accounts..." -ForegroundColor Yellow
    $updateScript = Join-Path $terraformRoot "scripts\update-hub-with-service-cidr.ps1"
    if (Test-Path $updateScript) {
        $cidrsString = $serviceVpcCidrs -join ","
        & $updateScript -ServiceVpcCidrs $cidrsString -Environment $Environment
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Hub Account actualizado" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Error al actualizar Hub Account" -ForegroundColor Red
        }
    } else {
        Write-Host "[ADVERTENCIA] Script de actualización no encontrado. Actualiza manualmente el Hub Account." -ForegroundColor Yellow
    }
}

# =============================================================================
# RESUMEN
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESUMEN DEL DESPLIEGUE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor White
Write-Host "Hub Account ID: $hubAccountId" -ForegroundColor White
Write-Host "Hub VPC CIDR: $hubVpcCidr" -ForegroundColor White
Write-Host "`nService Accounts desplegados: $($serviceAccounts.Count)" -ForegroundColor White

foreach ($account in $serviceAccounts) {
    Write-Host "  Service Account $($account.Number): $($account.AccountId) (VPC: $($account.VpcCidr))" -ForegroundColor Cyan
}

Write-Host "`n[OK] Proceso completado" -ForegroundColor Green
