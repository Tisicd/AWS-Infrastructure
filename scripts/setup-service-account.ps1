# =============================================================================
# Script de Configuración - Service Account
# =============================================================================
# Este script ayuda a configurar y desplegar la infraestructura en una cuenta service
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "qa", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$true)]
    [string]$HubAccountId,
    
    [Parameter(Mandatory=$true)]
    [string]$HubVpcCidr,
    
    [Parameter(Mandatory=$true)]
    [string]$HubDatabaseIp,
    
    [Parameter(Mandatory=$true)]
    [string]$HubKongEndpoint,
    
    [Parameter(Mandatory=$false)]
    [int]$AccountNumber = 1
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuración de Service Account" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Account Number: $AccountNumber" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Directorio de trabajo: $((Get-Location).Path)" -ForegroundColor Gray

# Verificar que Terraform está instalado
Write-Host "Verificando Terraform..." -ForegroundColor Yellow
$terraformCheck = Get-Command terraform -ErrorAction SilentlyContinue
if ($terraformCheck) {
    terraform version 2>&1 | Out-Null
    Write-Host "[OK] Terraform encontrado" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Terraform no esta instalado" -ForegroundColor Red
    exit 1
}

# Verificar credenciales AWS
Write-Host "`nVerificando credenciales AWS..." -ForegroundColor Yellow
try {
    $callerIdentityJson = aws sts get-caller-identity 2>&1
    if ($LASTEXITCODE -eq 0) {
        $callerIdentity = $callerIdentityJson | ConvertFrom-Json
        Write-Host "[OK] Credenciales validas" -ForegroundColor Green
        Write-Host "  Account ID: $($callerIdentity.Account)" -ForegroundColor Cyan
        Write-Host "  User ARN: $($callerIdentity.Arn)" -ForegroundColor Cyan
        
        if ($callerIdentity.Account -eq $HubAccountId) {
            Write-Host "`n[ADVERTENCIA] Estas usando la misma cuenta que el hub!" -ForegroundColor Yellow
            Write-Host "  Asegurate de haber cambiado las credenciales AWS" -ForegroundColor Yellow
            $confirm = Read-Host "¿Continuar de todas formas? (S/N)"
            if ($confirm -ne "S" -and $confirm -ne "s") {
                exit 0
            }
        }
    } else {
        throw "AWS CLI error"
    }
} catch {
    Write-Host "[ERROR] No se pueden obtener credenciales AWS" -ForegroundColor Red
    exit 1
}

# Crear directorio de despliegue
Write-Host "`nCreando directorio de despliegue..." -ForegroundColor Yellow
$deploymentDir = "deployments\service-account-$AccountNumber"
if (-not (Test-Path $deploymentDir)) {
    New-Item -ItemType Directory -Path $deploymentDir -Force | Out-Null
    Write-Host "[OK] Directorio creado: $deploymentDir" -ForegroundColor Green
} else {
    Write-Host "[OK] Directorio ya existe: $deploymentDir" -ForegroundColor Green
}

# Obtener información del VPC
Write-Host "`nObteniendo información de VPCs..." -ForegroundColor Yellow
try {
    $vpcs = aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output json | ConvertFrom-Json
    
    Write-Host "`nVPCs disponibles:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $vpcs.Count; $i++) {
        $vpc = $vpcs[$i]
        Write-Host "  [$i] VPC ID: $($vpc[0]) | CIDR: $($vpc[1]) | Name: $($vpc[2])" -ForegroundColor White
    }
    
    $vpcIndex = Read-Host "`nSelecciona el número del VPC que deseas usar"
    $selectedVpc = $vpcs[[int]$vpcIndex]
    $serviceVpcId = $selectedVpc[0]
    $serviceVpcCidr = $selectedVpc[1]
    
    Write-Host "[OK] VPC seleccionado: $serviceVpcId ($serviceVpcCidr)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Error al obtener VPCs" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Obtener subnets públicas
Write-Host "`nObteniendo subnets públicas..." -ForegroundColor Yellow
try {
    $subnets = aws ec2 describe-subnets `
        --filters "Name=vpc-id,Values=$serviceVpcId" "Name=map-public-ip-on-launch,Values=true" `
        --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' --output json | ConvertFrom-Json
    
    Write-Host "`nSubnets públicas disponibles:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subnets.Count; $i++) {
        $subnet = $subnets[$i]
        Write-Host "  [$i] Subnet: $($subnet[0]) | AZ: $($subnet[1]) | CIDR: $($subnet[2])" -ForegroundColor White
    }
    
    $publicSubnetIds = @()
    Write-Host "`nSelecciona las subnets que deseas usar (separadas por comas, ej: 0,1):" -ForegroundColor Yellow
    $selectedSubnets = Read-Host
    $selectedIndices = $selectedSubnets -split ','
    
    foreach ($index in $selectedIndices) {
        $publicSubnetIds += $subnets[[int]$index.Trim()][0]
    }
    
    Write-Host "[OK] Subnets seleccionadas: $($publicSubnetIds -join ', ')" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Error al obtener subnets" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Solicitar información adicional
Write-Host "`nInformación adicional requerida:" -ForegroundColor Yellow
$yourIpCidr = Read-Host "Tu IP pública en formato CIDR (ej: 157.100.135.84/32)"

# Verificar Key Pair - Terraform lo creará automáticamente si no existe
Write-Host "`nVerificando Key Pair..." -ForegroundColor Yellow
$keyPairName = "academic-platform-key"

# Verificar si el key pair ya existe
try {
    aws ec2 describe-key-pairs --key-names $keyPairName 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Key Pair '$keyPairName' ya existe en AWS" -ForegroundColor Green
        Write-Host "[INFO] Terraform usará el key pair existente (create_key_pair = false)" -ForegroundColor Cyan
        $createKeyPair = $false
    } else {
        Write-Host "[INFO] Key Pair '$keyPairName' no existe. Terraform lo creará automáticamente." -ForegroundColor Yellow
        $createKeyPair = $true
    }
} catch {
    Write-Host "[ADVERTENCIA] No se pudo verificar el Key Pair. Terraform intentará crearlo." -ForegroundColor Yellow
    $createKeyPair = $true
}

# Copiar archivo de configuración
Write-Host "`nCopiando archivo de configuración..." -ForegroundColor Yellow
$configSource = "environments\$Environment\terraform.tfvars.service"
$configDest = "$deploymentDir\terraform.tfvars"

if (Test-Path $configSource) {
    Copy-Item $configSource $configDest -Force
    Write-Host "[OK] Archivo copiado" -ForegroundColor Green
} else {
    Write-Host "[ERROR] No se encontro el archivo $configSource" -ForegroundColor Red
    exit 1
}

# Actualizar archivo de configuración
Write-Host "`nActualizando configuración..." -ForegroundColor Yellow
$configContent = Get-Content $configDest -Raw

# Reemplazar valores
$configContent = $configContent -replace 'account_type = "service"', 'account_type = "service"'
$configContent = $configContent -replace 'hub_account_id = "123456789012"', "hub_account_id = `"$HubAccountId`""
$configContent = $configContent -replace 'hub_vpc_cidr = "10.0.0.0/16"', "hub_vpc_cidr = `"$HubVpcCidr`""
$configContent = $configContent -replace 'vpc_id = "vpc-XXXXXXXX"', "vpc_id = `"$serviceVpcId`""
$configContent = $configContent -replace 'database_host_override = "10.0.X.X"', "database_host_override = `"$HubDatabaseIp`""
$configContent = $configContent -replace 'redis_host_override = "10.0.X.X"', "redis_host_override = `"$HubDatabaseIp`""
$configContent = $configContent -replace 'kong_endpoint_override = "http://10.0.X.X:8000"', "kong_endpoint_override = `"$HubKongEndpoint`""
$configContent = $configContent -replace 'your_ip_cidr = "157.100.135.84/32"', "your_ip_cidr = `"$yourIpCidr`""
$configContent = $configContent -replace 'key_pair_name = "academic-platform-key"', "key_pair_name = `"$keyPairName`""

# Configurar creación de key pair
if ($configContent -match 'create_key_pair\s*=') {
    $configContent = $configContent -replace 'create_key_pair\s*=\s*(true|false)', "create_key_pair = $($createKeyPair.ToString().ToLower())"
} else {
    # Agregar después de key_pair_name
    $configContent = $configContent -replace '(key_pair_name\s*=\s*"[^"]+")', "`$1`ncreate_key_pair = $($createKeyPair.ToString().ToLower())`nsave_key_pair_locally = true"
}

# Actualizar subnets
$subnetArray = ($publicSubnetIds | ForEach-Object { "`"$_`"" }) -join ','
$configContent = $configContent -replace 'public_subnet_ids = \[.*?\]', "public_subnet_ids = [$subnetArray]"

Set-Content $configDest $configContent
Write-Host "[OK] Configuracion actualizada" -ForegroundColor Green

# Limpiar estado de Terraform antes de inicializar
Write-Host "`nLimpiando estado de Terraform..." -ForegroundColor Yellow
$terraformRoot = (Get-Location).Path
Set-Location $terraformRoot

# Eliminar cualquier estado residual que pueda tener referencias al hub account
if (Test-Path "terraform.tfstate") {
    Remove-Item "terraform.tfstate" -Force
    Write-Host "[OK] Estado principal eliminado" -ForegroundColor Green
}
if (Test-Path "terraform.tfstate.backup") {
    Remove-Item "terraform.tfstate.backup" -Force
    Write-Host "[OK] Backup eliminado" -ForegroundColor Green
}

# Inicializar Terraform (desde directorio raíz, no desde deploymentDir)
Write-Host "`nInicializando Terraform..." -ForegroundColor Yellow
terraform init
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Terraform inicializado" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Error al inicializar Terraform" -ForegroundColor Red
    exit 1
}

# Validar configuración
Write-Host "`nValidando configuracion..." -ForegroundColor Yellow
terraform validate
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Configuracion valida" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Error en la configuracion" -ForegroundColor Red
    exit 1
}

# Mostrar plan (usando -var-file con ruta completa)
Write-Host "`nGenerando plan de despliegue..." -ForegroundColor Yellow
$tfvarsPathObj = Resolve-Path "$deploymentDir\terraform.tfvars" -ErrorAction Stop
$tfvarsPath = $tfvarsPathObj.Path

# Verificar que el archivo existe antes de ejecutar terraform
if (-not (Test-Path $tfvarsPath)) {
    Write-Host "[ERROR] El archivo terraform.tfvars no existe en: $tfvarsPath" -ForegroundColor Red
    exit 1
}

# Usar -var-file sin = para evitar problemas de parsing en PowerShell
# Si la ruta tiene espacios, usar comillas alrededor del path
if ($tfvarsPath -match '\s') {
    terraform plan -var-file="$tfvarsPath"
} else {
    terraform plan -var-file $tfvarsPath
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Resumen de configuración:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Account Type: service" -ForegroundColor White
Write-Host "Hub Account ID: $HubAccountId" -ForegroundColor White
Write-Host "Hub VPC CIDR: $HubVpcCidr" -ForegroundColor White
Write-Host "VPC ID: $serviceVpcId" -ForegroundColor White
Write-Host "VPC CIDR: $serviceVpcCidr" -ForegroundColor White
Write-Host "Database Host: $HubDatabaseIp" -ForegroundColor White
Write-Host "Kong Endpoint: $HubKongEndpoint" -ForegroundColor White
Write-Host "`n¿Deseas aplicar estos cambios? (S/N):" -ForegroundColor Yellow
$confirm = Read-Host

if ($confirm -eq "S" -or $confirm -eq "s") {
    Write-Host "`nAplicando cambios..." -ForegroundColor Yellow
    $tfvarsPathObj = Resolve-Path "$deploymentDir\terraform.tfvars" -ErrorAction Stop
    $tfvarsPath = $tfvarsPathObj.Path
    
    # Verificar que el archivo existe antes de ejecutar terraform
    if (-not (Test-Path $tfvarsPath)) {
        Write-Host "[ERROR] El archivo terraform.tfvars no existe en: $tfvarsPath" -ForegroundColor Red
        exit 1
    }
    
    # Usar -var-file sin = para evitar problemas de parsing en PowerShell
    # Si la ruta tiene espacios, usar comillas alrededor del path
    if ($tfvarsPath -match '\s') {
        terraform apply -var-file="$tfvarsPath" -auto-approve
    } else {
        terraform apply -var-file $tfvarsPath -auto-approve
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[OK] Despliegue completado exitosamente!" -ForegroundColor Green
        
        # Guardar outputs
        Write-Host "`nGuardando outputs..." -ForegroundColor Yellow
        $outputPath = Resolve-Path "$deploymentDir" | Join-Path -ChildPath "service-outputs.json"
        terraform output -json | Out-File -FilePath $outputPath -Encoding UTF8
        
        Write-Host "`nOutputs importantes:" -ForegroundColor Cyan
        terraform output microservices_asg_name
        terraform output vpc_cidr_block
        terraform output current_account_id
        
        Write-Host "`n[IMPORTANTE] Ahora debes actualizar el hub account con el CIDR de esta service account" -ForegroundColor Yellow
        Write-Host "  Service VPC CIDR: $serviceVpcCidr" -ForegroundColor Cyan
    } else {
        Write-Host "[ERROR] Error durante el despliegue" -ForegroundColor Red
        exit 1
    }
} else {
    $tfvarsPathObj = Resolve-Path "$deploymentDir\terraform.tfvars" -ErrorAction SilentlyContinue
    if ($tfvarsPathObj) {
        $tfvarsPath = $tfvarsPathObj.Path
        Write-Host "`nDespliegue cancelado. Puedes ejecutar 'terraform apply -var-file=`"$tfvarsPath`"' manualmente cuando estes listo." -ForegroundColor Yellow
    } else {
        Write-Host "`nDespliegue cancelado. Puedes ejecutar 'terraform apply -var-file=deployments\service-account\terraform.tfvars' manualmente cuando estes listo." -ForegroundColor Yellow
    }
}

Write-Host "`n[OK] Proceso completado" -ForegroundColor Green
