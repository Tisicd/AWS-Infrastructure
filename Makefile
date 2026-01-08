.PHONY: init plan apply destroy fmt validate clean

# Initialize Terraform
init:
	terraform init

# Generate execution plan
plan:
	terraform plan -var-file=terraform.tfvars -out=tfplan

# Apply changes
apply:
	terraform apply -var-file=terraform.tfvars

# Apply using saved plan
apply-plan:
	terraform apply tfplan

# Destroy infrastructure
destroy:
	terraform destroy -var-file=terraform.tfvars -auto-approve

# Format Terraform code
fmt:
	terraform fmt -recursive

# Validate Terraform configuration
validate:
	terraform validate

# Clean Terraform files
clean:
	rm -rf .terraform .terraform.lock.hcl tfplan *.tfplan







