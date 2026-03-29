@echo off
cd /d "%~dp0"
echo Building Clausage...
dotnet build Clausage\Clausage.csproj -c Release
if %ERRORLEVEL% NEQ 0 (
    echo Build failed.
    pause
    exit /b 1
)
echo Build succeeded.
echo Run: dotnet run --project Clausage\Clausage.csproj -c Release
pause
