@echo off
cd /d "%~dp0"
echo Publishing Clausage as single-file exe...
dotnet publish Clausage\Clausage.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish
if %ERRORLEVEL% NEQ 0 (
    echo Publish failed.
    pause
    exit /b 1
)
echo.
echo Published to: publish\Clausage.exe
echo You can copy this single file anywhere and run it.
pause
