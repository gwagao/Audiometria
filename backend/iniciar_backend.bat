@echo off
rem Inicia el backend de Audiometria en el puerto 8000, accesible desde el telefono por la red local.
cd /d "%~dp0"
if not exist .venv (
    echo Creando entorno virtual...
    python -m venv .venv || goto :error
    .venv\Scripts\python -m pip install --upgrade pip
    .venv\Scripts\python -m pip install -r requirements.txt || goto :error
)
echo.
echo Direcciones IP de este equipo (usa una en la app: http://IP:8000):
ipconfig | findstr /c:"IPv4"
echo.
.venv\Scripts\python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
goto :eof

:error
echo.
echo ERROR: no se pudo preparar el entorno. Verifica que Python 3.10+ este instalado.
pause
