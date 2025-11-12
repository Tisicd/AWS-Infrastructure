# Imagen base oficial de Python
FROM python:3.12-slim

# Carpeta de trabajo dentro del contenedor
WORKDIR /app

# Copiar archivo de dependencias e instalarlas
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copiar todo el código de la app
COPY . .

# Exponer el puerto 8080
EXPOSE 8080

# Comando para ejecutar la app
CMD ["python", "app.py"]
