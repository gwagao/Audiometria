# Audiometría

App Android para realizar una audiometría tonal de cribado con tonos puros.

- `app/` — aplicación Flutter (Android): prueba, audiograma, historial y compartir.
- `backend/` — servidor Python (FastAPI): análisis, gráfico del audiograma e informe PDF.

## Requisitos

| Para | Necesitas | Versión usada |
|---|---|---|
| Backend | Python | 3.12 (sirve 3.10+) |
| Backend | Paquetes de `backend/requirements.txt` | fastapi, uvicorn, pydantic, matplotlib, reportlab |
| App | Flutter SDK | 3.47.7 estable |
| App | Git | 2.56 (lo exige Flutter) |
| App | JDK | 17 o superior |
| App | Android SDK (cmdline-tools, platform-tools, plataforma y build-tools) | los descarga Gradle al compilar |
| Uso | Teléfono Android 7.0+ y audífonos (mejor con cable) | |
| Uso | Teléfono y computador en la misma red Wi-Fi | para generar el PDF |

En este equipo quedaron instalados en `C:\Users\gwagao\dev\` (`flutter`, `mingit`,
`android-sdk`) y Python en `%LOCALAPPDATA%\Programs\Python\Python312`. Flutter y Git no
están en el PATH global; para usarlos en una terminal PowerShell:

```powershell
$env:PATH = "C:\Users\gwagao\dev\mingit\cmd;C:\Users\gwagao\dev\flutter\bin;$env:PATH"
```

## 1. Iniciar el backend

Doble clic en `backend\iniciar_backend.bat`. La primera vez crea el entorno virtual e
instala los requisitos; después muestra la IP del equipo y deja el servidor en el puerto 8000.
Si Windows pregunta por el firewall, permite el acceso en redes privadas.

Manual:

```powershell
cd backend
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Documentación interactiva de la API: <http://localhost:8000/docs>.
Tests: `.venv\Scripts\python -m pip install -r requirements-dev.txt` y `.venv\Scripts\python -m pytest`.

## 2. Compilar e instalar la app

```powershell
cd app
flutter build apk --release
```

El APK queda en `app\build\app\outputs\flutter-apk\app-release.apk`. Cópialo al teléfono e
instálalo, o con el teléfono conectado por USB (depuración activada): `flutter install`.

## 3. Usar la app

1. **Ajustes → URL del backend**: escribe `http://IP-DEL-COMPUTADOR:8000` y pulsa
   *Probar conexión*.
2. Conecta los audífonos: la pantalla principal muestra cuáles reconoció (cable, USB o Bluetooth).
3. **Nueva prueba**: datos del paciente, comprueba izquierdo/derecho y comienza.
4. Durante la prueba pulsa **Lo escucho** cada vez que oigas un tono. El tono empieza suave y
   sube de intensidad hasta que respondes; luego baja 10 dB y vuelve a subir de 5 en 5 dB
   (método Hughson-Westlake). Primero el oído derecho, luego el izquierdo.
5. **Resultado**: audiograma, promedio tonal y clasificación (OMS) por oído.
   *Generar PDF y compartir* pide el informe al backend y abre el menú de compartir de Android
   (WhatsApp, correo, Drive…). *Compartir resumen en texto* funciona sin servidor.

Las pruebas se guardan en el **Historial** del teléfono; el backend guarda además una copia
en `backend\data\audiometria.db`.

## Calibración y límites

Un teléfono no conoce la sensibilidad de los audífonos, así que los dB HL son aproximados:
la app asume que un tono a escala completa con el volumen al máximo produce 100 dB SPL y
aplica los niveles de referencia RETSPL por frecuencia. Para corregirlo, en
**Ajustes → Calibración** una persona con audición normal ajusta el control hasta que el tono
de 1 kHz apenas se escuche.

- Usa siempre los mismos audífonos con los que calibraste; mejor con cable (Bluetooth altera el nivel).
- Si Android muestra el aviso de volumen alto, acéptalo: la prueba necesita el volumen al máximo.
- El nivel máximo presentado es 80 dB HL por defecto (configurable).
- Es una herramienta de cribado orientativa: **no sustituye una audiometría clínica** ni
  constituye un diagnóstico médico.
