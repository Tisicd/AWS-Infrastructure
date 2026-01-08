FROM hashicorp/terraform:1.13.0

WORKDIR /workspace

COPY . .

# Sobrescribir entrypoint para permitir comandos completos
ENTRYPOINT []
CMD ["terraform", "--version"]