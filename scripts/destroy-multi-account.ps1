# =============================================================================
# Script de Destroy Multi-Cuenta
# =============================================================================
# Este script destruye la infraestructura cuenta por cuenta
# Comienza con el hub account, luego service accounts
# Espera confirmacion y cambio de credenciales entre cada cuenta
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "qa", "prod")]
    [string]$Environment = "qa",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipHubAccount = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipServiceAccounts = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoConfirm = $false
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Destroy Multi-Cuenta" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar herramientas
Write-Host "Verificando herramientas..." -ForegroundColor Yellow
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Terraform no encontrado" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] AWS CLI no encontrado" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Herramientas verificadas" -ForegroundColor Green
Write-Host ""

# Directorio de trabajo
$terraformRoot = (Get-Location).Path
if (-not (Test-Path "main.tf")) {
    Write-Host "[ERROR] Este script debe ejecutarse desde el directorio raiz de Terraform" -ForegroundColor Red
    Write-Host "  Directorio actual: $terraformRoot" -ForegroundColor Yellow
    exit 1
}

# Función para verificar credenciales AWS
function Test-AwsCredentials {
    try {
        $callerIdentity = aws sts get-caller-identity 2>&1
        if ($LASTEXITCODE -eq 0) {
            $identity = $callerIdentity | ConvertFrom-Json
            Write-Host "[OK] Credenciales validas" -ForegroundColor Green
            Write-Host "  Account ID: $($identity.Account)" -ForegroundColor Cyan
            Write-Host "  User ARN: $($identity.Arn)" -ForegroundColor Cyan
            return $identity.Account
        } else {
            Write-Host "[ERROR] Credenciales AWS invalidas" -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "[ERROR] Error al verificar credenciales AWS" -ForegroundColor Red
        return $null
    }
}

# Función para detectar recursos en AWS
function Find-AwsResources {
    param(
        [string]$ProjectName = "academic-platform",
        [string]$Environment = "qa"
    )
    
    Write-Host "Verificando recursos en AWS..." -ForegroundColor Yellow
    
    $resourcesFound = @{
        Instances = @()
        ElasticIPs = @()
        LoadBalancers = @()
        TargetGroups = @()
        AutoScalingGroups = @()
        SecurityGroups = @()
        CloudWatchLogGroups = @()
        TotalCount = 0
    }
    
    try {
        # Buscar instancias EC2
        $instanceQuery = "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name'].Value|[0],State.Name,PrivateIpAddress,PublicIpAddress]"
        $instanceFilter1 = "Name=tag:Name,Values=$ProjectName-$Environment-*"
        $instanceFilter2 = "Name=instance-state-name,Values=running,stopped,stopping"
        $instancesOutput = aws ec2 describe-instances --filters $instanceFilter1 $instanceFilter2 --query $instanceQuery --output text 2>&1
        if ($LASTEXITCODE -eq 0 -and $instancesOutput -match '\S') {
            $instances = ($instancesOutput -split "`n" | Where-Object { $_.Trim() -ne "" })
            foreach ($instance in $instances) {
                $parts = $instance -split "`t"
                if ($parts.Count -ge 3) {
                    $resourcesFound.Instances += @{
                        InstanceId = $parts[0]
                        Name = if ($parts[1]) { $parts[1] } else { "N/A" }
                        State = $parts[2]
                        PrivateIP = if ($parts.Count -gt 3) { $parts[3] } else { "N/A" }
                        PublicIP = if ($parts.Count -gt 4) { $parts[4] } else { "N/A" }
                    }
                }
            }
        }
        
        # Buscar Elastic IPs
        $eipQuery = "Addresses[*].[AllocationId,PublicIp,AssociationId,Tags[?Key=='Name'].Value|[0]]"
        $eipFilter = "Name=tag:Name,Values=$ProjectName-$Environment-*"
        $eipsOutput = aws ec2 describe-addresses --filters $eipFilter --query $eipQuery --output text 2>&1
        if ($LASTEXITCODE -eq 0 -and $eipsOutput -match '\S') {
            $eips = ($eipsOutput -split "`n" | Where-Object { $_.Trim() -ne "" })
            foreach ($eip in $eips) {
                $parts = $eip -split "`t"
                if ($parts.Count -ge 2) {
                    $resourcesFound.ElasticIPs += @{
                        AllocationId = $parts[0]
                        PublicIP = $parts[1]
                        AssociationId = if ($parts.Count -gt 2 -and $parts[2] -ne "None") { $parts[2] } else { "No asociada" }
                        Name = if ($parts.Count -gt 3) { $parts[3] } else { "N/A" }
                    }
                }
            }
        }
        
        # Buscar Load Balancers
        $lbQuery = "LoadBalancers[?contains(LoadBalancerName, '$ProjectName-$Environment')].[LoadBalancerArn,LoadBalancerName,DNSName,State.Code]"
        $lbOutput = aws elbv2 describe-load-balancers --query $lbQuery --output text 2>&1
        if ($LASTEXITCODE -eq 0 -and $lbOutput -match '\S') {
            $lbs = ($lbOutput -split "`n" | Where-Object { $_.Trim() -ne "" })
            foreach ($lb in $lbs) {
                $parts = $lb -split "`t"
                if ($parts.Count -ge 2) {
                    $resourcesFound.LoadBalancers += @{
                        ARN = $parts[0]
                        Name = $parts[1]
                        DNS = if ($parts.Count -gt 2) { $parts[2] } else { "N/A" }
                        State = if ($parts.Count -gt 3) { $parts[3] } else { "N/A" }
                    }
                }
            }
        }
        
        # Buscar Target Groups
        $tgQuery = "TargetGroups[?contains(TargetGroupName, '$ProjectName-$Environment')].[TargetGroupArn,TargetGroupName,HealthCheckProtocol]"
        $tgOutput = aws elbv2 describe-target-groups --query $tgQuery --output text 2>&1
        if ($LASTEXITCODE -eq 0 -and $tgOutput -match '\S') {
            $tgs = ($tgOutput -split "`n" | Where-Object { $_.Trim() -ne "" })
            foreach ($tg in $tgs) {
                $parts = $tg -split "`t"
                if ($parts.Count -ge 2) {
                    $resourcesFound.TargetGroups += @{
                        ARN = $parts[0]
                        Name = $parts[1]
                        Protocol = if ($parts.Count -gt 2) { $parts[2] } else { "N/A" }
                    }
                }
            }
        }
        
        # Buscar Auto Scaling Groups
        $asgQuery = "AutoScalingGroups[?contains(AutoScalingGroupName, '$ProjectName-$Environment')].[AutoScalingGroupName,DesiredCapacity,MinSize,MaxSize,Instances[].InstanceId]"
        $asgOutput = aws autoscaling describe-auto-scaling-groups --query $asgQuery --output text 2>&1
        if ($LASTEXITCODE -eq 0 -and $asgOutput -match '\S') {
            $asgs = ($asgOutput -split "`n" | Where-Object { $_.Trim() -ne "" })
            foreach ($asg in $asgs) {
                $parts = $asg -split "`t"
                if ($parts.Count -ge 1) {
                    $resourcesFound.AutoScalingGroups += @{
                        Name = $parts[0]
                        Desired = if ($parts.Count -gt 1) { $parts[1] } else { "N/A" }
                        MinSize = if ($parts.Count -gt 2) { $parts[2] } else { "N/A" }
                        MaxSize = if ($parts.Count -gt 3) { $parts[3] } else { "N/A" }
                    }
                }
            }
        }
        
        # Buscar Security Groups
        $sgQuery = "SecurityGroups[?contains(GroupName, '$ProjectName-$Environment')].[GroupId,GroupName,Description]"
        $sgOutput = aws ec2 describe-security-groups --query $sgQuery --output text 2>&1
        if ($LASTEXITCODE -eq 0 -and $sgOutput -match '\S') {
            $sgs = ($sgOutput -split "`n" | Where-Object { $_.Trim() -ne "" })
            foreach ($sg in $sgs) {
                $parts = $sg -split "`t"
                if ($parts.Count -ge 2) {
                    $resourcesFound.SecurityGroups += @{
                        GroupId = $parts[0]
                        GroupName = $parts[1]
                        Description = if ($parts.Count -gt 2) { $parts[2] } else { "N/A" }
                    }
                }
            }
        }
        
        # Buscar CloudWatch Log Groups
        $logGroupPrefix = "/aws/$ProjectName/$Environment"
        $logGroupsOutput = aws logs describe-log-groups --log-group-name-prefix $logGroupPrefix --query "logGroups[*].[logGroupName]" --output text 2>&1
        if ($LASTEXITCODE -eq 0 -and $logGroupsOutput -match '\S') {
            $logGroups = ($logGroupsOutput -split "`n" | Where-Object { $_.Trim() -ne "" })
            foreach ($logGroup in $logGroups) {
                if ($logGroup.Trim() -ne "") {
                    $resourcesFound.CloudWatchLogGroups += @{
                        LogGroupName = $logGroup.Trim()
                    }
                }
            }
        }
        
        # Contar total
        $resourcesFound.TotalCount = $resourcesFound.Instances.Count + $resourcesFound.ElasticIPs.Count + $resourcesFound.LoadBalancers.Count + $resourcesFound.TargetGroups.Count + $resourcesFound.AutoScalingGroups.Count + $resourcesFound.SecurityGroups.Count + $resourcesFound.CloudWatchLogGroups.Count
        
        return $resourcesFound
    } catch {
        Write-Host "[WARN] Error al verificar recursos en AWS: $($_.Exception.Message)" -ForegroundColor Yellow
        return $resourcesFound
    }
}

# Función para eliminar recursos directamente con AWS CLI
function Remove-AwsResources {
    param(
        [hashtable]$Resources,
        [string]$ProjectName = "academic-platform",
        [string]$Environment = "qa"
    )
    
    $deletedCount = 0
    $errors = @()
    
    # Eliminar Auto Scaling Groups primero (esto terminará instancias)
    foreach ($asg in $Resources.AutoScalingGroups) {
        try {
            aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $asg.Name --force 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
                Start-Sleep -Seconds 2
            } else {
                $errors += "ASG: $($asg.Name)"
            }
        } catch {
            $errors += "ASG: $($asg.Name)"
        }
    }
    
    # Eliminar Load Balancers (deben eliminarse antes de target groups)
    foreach ($lb in $Resources.LoadBalancers) {
        try {
            aws elbv2 delete-load-balancer --load-balancer-arn $lb.ARN 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
                Start-Sleep -Seconds 2
            } else {
                $errors += "LB: $($lb.Name)"
            }
        } catch {
            $errors += "LB: $($lb.Name)"
        }
    }
    
    # Esperar a que los load balancers se eliminen antes de target groups
    if ($Resources.LoadBalancers.Count -gt 0) {
        Start-Sleep -Seconds 10
    }
    
    # Eliminar Target Groups
    foreach ($tg in $Resources.TargetGroups) {
        try {
            aws elbv2 delete-target-group --target-group-arn $tg.ARN 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
            } else {
                $errors += "TG: $($tg.Name)"
            }
        } catch {
            $errors += "TG: $($tg.Name)"
        }
    }
    
    # Terminar instancias EC2 (si no fueron eliminadas por ASG)
    foreach ($instance in $Resources.Instances) {
        try {
            aws ec2 terminate-instances --instance-ids $instance.InstanceId 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
            } else {
                $errors += "EC2: $($instance.InstanceId)"
            }
        } catch {
            $errors += "EC2: $($instance.InstanceId)"
        }
    }
    
    # Desasociar y liberar Elastic IPs
    foreach ($eip in $Resources.ElasticIPs) {
        try {
            if ($eip.AssociationId -ne "No asociada") {
                aws ec2 disassociate-address --association-id $eip.AssociationId 2>&1 | Out-Null
                Start-Sleep -Seconds 1
            }
            aws ec2 release-address --allocation-id $eip.AllocationId 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
            } else {
                $errors += "EIP: $($eip.AllocationId)"
            }
        } catch {
            $errors += "EIP: $($eip.AllocationId)"
        }
    }
    
    # Eliminar CloudWatch Log Groups
    foreach ($logGroup in $Resources.CloudWatchLogGroups) {
        try {
            aws logs delete-log-group --log-group-name $logGroup.LogGroupName 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
            } else {
                $errors += "LogGroup: $($logGroup.LogGroupName)"
            }
        } catch {
            $errors += "LogGroup: $($logGroup.LogGroupName)"
        }
    }
    
    # Esperar antes de eliminar Security Groups (deben eliminarse después de instancias)
    if ($Resources.Instances.Count -gt 0) {
        Start-Sleep -Seconds 30
    }
    
    # Eliminar Security Groups (solo los que no están en uso)
    foreach ($sg in $Resources.SecurityGroups) {
        try {
            # Intentar eliminar el security group (fallará si está en uso)
            aws ec2 delete-security-group --group-id $sg.GroupId 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
            } else {
                # Si falla, es probable que esté en uso, intentar con force (remover reglas primero)
                $rulesOutput = aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$($sg.GroupId)" --query "SecurityGroupRules[*].SecurityGroupRuleId" --output text 2>&1
                if ($LASTEXITCODE -eq 0 -and $rulesOutput -match '\S') {
                    $ruleIds = ($rulesOutput -split "`t" | Where-Object { $_.Trim() -ne "" })
                    foreach ($ruleId in $ruleIds) {
                        aws ec2 revoke-security-group-egress --group-id $sg.GroupId --security-group-rule-ids $ruleId 2>&1 | Out-Null
                        aws ec2 revoke-security-group-ingress --group-id $sg.GroupId --security-group-rule-ids $ruleId 2>&1 | Out-Null
                    }
                    Start-Sleep -Seconds 2
                    aws ec2 delete-security-group --group-id $sg.GroupId 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        $deletedCount++
                    } else {
                        $errors += "SG: $($sg.GroupName)"
                    }
                } else {
                    $errors += "SG: $($sg.GroupName)"
                }
            }
        } catch {
            $errors += "SG: $($sg.GroupName)"
        }
    }
    
    if ($errors.Count -gt 0) {
        Write-Host "[WARN] $($errors.Count) recursos tuvieron errores" -ForegroundColor Yellow
    }
    
    return @{
        DeletedCount = $deletedCount
        Errors = $errors
    }
}

# Función para destruir una cuenta
function Destroy-Account {
    param(
        [string]$AccountType,
        [string]$DeploymentDir,
        [string]$AccountNumber = "",
        [string]$Environment = "qa"
    )
    
    $accountLabel = if ($AccountNumber -ne "") {
        "$AccountType Account $AccountNumber"
    } else {
        "$AccountType Account"
    }
    
    Write-Host "Destroy: $accountLabel" -ForegroundColor Cyan
    
    # Verificar que el directorio existe
    if (-not (Test-Path $DeploymentDir)) {
        Write-Host "[SKIP] Directorio no existe" -ForegroundColor Yellow
        return $false
    }
    
    # Verificar credenciales
    $currentAccountId = Test-AwsCredentials
    if (-not $currentAccountId) {
        Write-Host "[ERROR] No se pueden verificar credenciales AWS" -ForegroundColor Red
        Write-Host "  Configura las credenciales y vuelve a intentar" -ForegroundColor Yellow
        return $false
    }
    
    try {
        # Detectar recursos en AWS
        $awsResources = Find-AwsResources -ProjectName "academic-platform" -Environment $Environment
        
        if ($awsResources.TotalCount -eq 0) {
            Write-Host "[OK] No hay recursos en AWS" -ForegroundColor Green
            return $true
        }
        
        Write-Host "Recursos encontrados: $($awsResources.TotalCount)" -ForegroundColor Yellow
        
        # Verificar estado de Terraform
        $stateFiles = @("terraform.tfstate", "terraform.tfstate.backup")
        $hasState = $false
        
        foreach ($stateFile in $stateFiles) {
            $statePathInRoot = Join-Path $terraformRoot $stateFile
            if (Test-Path $statePathInRoot) {
                $hasState = $true
                break
            }
            $statePathInDeployment = Join-Path $DeploymentDir $stateFile
            if (Test-Path $statePathInDeployment) {
                $hasState = $true
                break
            }
        }
        
        # Si hay recursos en AWS pero no hay estado de Terraform, eliminarlos directamente con AWS CLI
        if (-not $hasState -and $awsResources.TotalCount -gt 0) {
            Write-Host "Eliminando recursos directamente con AWS CLI..." -ForegroundColor Yellow
            $deleteResult = Remove-AwsResources -Resources $awsResources -ProjectName "academic-platform" -Environment $Environment
            
            if ($deleteResult.DeletedCount -gt 0) {
                Write-Host "[OK] $($deleteResult.DeletedCount) recursos eliminados" -ForegroundColor Green
                if ($deleteResult.Errors.Count -gt 0) {
                    Write-Host "[WARN] $($deleteResult.Errors.Count) errores" -ForegroundColor Yellow
                }
                return $true
            } else {
                Write-Host "[ERROR] No se pudieron eliminar los recursos" -ForegroundColor Red
                return $false
            }
        }
        
        # Si hay estado, intentar usar Terraform primero
        if ($hasState) {
            $tfvarsPath = Join-Path $DeploymentDir "terraform.tfvars"
            if (Test-Path $tfvarsPath) {
                $tfvarsFullPath = (Resolve-Path $tfvarsPath).Path
                Push-Location $terraformRoot
                
                try {
                    # Inicializar Terraform si es necesario
                    if (-not (Test-Path ".terraform")) {
                        terraform init -upgrade 2>&1 | Out-Null
                    }
                    
                    # Ejecutar terraform destroy usando array de argumentos para evitar problemas con espacios
                    $terraformArgs = @("destroy", "-auto-approve", "-var-file=$tfvarsFullPath")
                    & terraform $terraformArgs 2>&1 | Out-Null
                    $destroyExitCode = $LASTEXITCODE
                    
                    Pop-Location
                    
                    if ($destroyExitCode -eq 0) {
                        Write-Host "[OK] Destroy completado" -ForegroundColor Green
                        return $true
                    }
                } catch {
                    Pop-Location
                }
            }
        }
        
        # Si Terraform no funcionó o no hay estado, usar AWS CLI directamente
        Write-Host "Eliminando recursos con AWS CLI..." -ForegroundColor Yellow
        $deleteResult = Remove-AwsResources -Resources $awsResources -ProjectName "academic-platform" -Environment $Environment
        
        if ($deleteResult.DeletedCount -gt 0) {
            Write-Host "[OK] $($deleteResult.DeletedCount) recursos eliminados" -ForegroundColor Green
            if ($deleteResult.Errors.Count -gt 0) {
                Write-Host "[WARN] $($deleteResult.Errors.Count) errores" -ForegroundColor Yellow
            }
            return $true
        } else {
            Write-Host "[ERROR] No se pudieron eliminar los recursos" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "[ERROR] Error inesperado: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Detectar deployments existentes
Write-Host "Detectando deployments existentes..." -ForegroundColor Yellow
$deploymentsDir = "deployments"
$hubAccountDir = Join-Path $deploymentsDir "hub-account"
$serviceAccountDirs = @()

# Buscar service accounts
$serviceAccounts = Get-ChildItem -Path $deploymentsDir -Directory | Where-Object { $_.Name -like "service-account-*" } | Sort-Object Name

foreach ($sa in $serviceAccounts) {
    $serviceAccountDirs += $sa.FullName
}

$hubExists = if (Test-Path $hubAccountDir) { "SI" } else { "NO" }
Write-Host "Hub Account: $hubExists | Service Accounts: $($serviceAccountDirs.Count)" -ForegroundColor Cyan
Write-Host ""

# Confirmar inicio (saltar si AutoConfirm está habilitado)
if (-not $AutoConfirm) {
    Write-Host ""
    try {
        $startConfirm = Read-Host "Deseas continuar con el destroy de todas las cuentas? (S/N)"
        if ($startConfirm -ne "S" -and $startConfirm -ne "s") {
            Write-Host "[CANCEL] Operacion cancelada" -ForegroundColor Yellow
            exit 0
        }
    } catch {
        Write-Host "[INFO] Modo no interactivo - continuando automaticamente" -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] Modo AutoConfirm - continuando automaticamente" -ForegroundColor Yellow
}

# Destruir Hub Account primero
$destroyedAccounts = @()
$failedAccounts = @()

if (-not $SkipHubAccount) {
    if (Test-Path $hubAccountDir) {
        Write-Host ""
        Write-Host "=== Hub Account ===" -ForegroundColor Cyan
        
        $ready = "S"
        if (-not $AutoConfirm) {
            try {
                $ready = Read-Host "Credenciales del Hub Account configuradas? (S/N)"
            } catch {
                $ready = "S"
            }
        }
        if ($ready -eq "S" -or $ready -eq "s") {
            $success = Destroy-Account -AccountType "Hub" -DeploymentDir $hubAccountDir -Environment $Environment
            if ($success) {
                $destroyedAccounts += "Hub Account"
            } else {
                $failedAccounts += "Hub Account"
            }
        } else {
            Write-Host "[SKIP] Hub Account omitido por el usuario" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[SKIP] Hub Account no encontrado" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Hub Account omitido por parametro" -ForegroundColor Yellow
}

# Destruir Service Accounts
if (-not $SkipServiceAccounts) {
    if ($serviceAccountDirs.Count -gt 0) {
        Write-Host ""
        Write-Host "PASO 2: Destroy Service Accounts" -ForegroundColor Cyan
        Write-Host "Total de Service Accounts: $($serviceAccountDirs.Count)" -ForegroundColor Yellow
        Write-Host ""
        
        for ($i = 0; $i -lt $serviceAccountDirs.Count; $i++) {
            $saDir = $serviceAccountDirs[$i]
            $saName = Split-Path -Leaf $saDir
            $saNumber = $saName -replace "service-account-", ""
            
            Write-Host ""
            Write-Host "=== Service Account $saNumber ($($i + 1)/$($serviceAccountDirs.Count)) ===" -ForegroundColor Cyan
            
            $ready = "S"
            if (-not $AutoConfirm) {
                try {
                    $ready = Read-Host "Credenciales de Service Account $saNumber configuradas? (S/N)"
                } catch {
                    $ready = "S"
                }
            }
            if ($ready -eq "S" -or $ready -eq "s") {
                $success = Destroy-Account -AccountType "Service" -DeploymentDir $saDir -AccountNumber $saNumber -Environment $Environment
                if ($success) {
                    $destroyedAccounts += "Service Account $saNumber"
                } else {
                    $failedAccounts += "Service Account $saNumber"
                }
            } else {
                Write-Host "[SKIP] Service Account $saNumber omitido por el usuario" -ForegroundColor Yellow
            }
            
            # Pausa entre cuentas (excepto la última)
            if ($i -lt $serviceAccountDirs.Count - 1) {
                Write-Host ""
                Write-Host "Pausa: Preparate para la siguiente Service Account" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "[SKIP] No se encontraron Service Accounts" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Service Accounts omitidos por parametro" -ForegroundColor Yellow
}

# Resumen final
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Resumen de Destroy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($destroyedAccounts.Count -gt 0) {
    Write-Host "Cuentas destruidas exitosamente ($($destroyedAccounts.Count)):" -ForegroundColor Green
    foreach ($account in $destroyedAccounts) {
        Write-Host "  [OK] $account" -ForegroundColor Green
    }
    Write-Host ""
}

if ($failedAccounts.Count -gt 0) {
    Write-Host "Cuentas con errores ($($failedAccounts.Count)):" -ForegroundColor Red
    foreach ($account in $failedAccounts) {
        Write-Host "  [ERROR] $account" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Revisa los errores y ejecuta el script nuevamente para las cuentas fallidas" -ForegroundColor Yellow
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Destroy Multi-Cuenta completado" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
