@echo off
echo Checking for .NET SDK...
dotnet --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo .NET SDK already installed:
    dotnet --version
    pause
    exit /b 0
)
echo .NET SDK not found. Installing .NET 8 SDK...
winget install Microsoft.DotNet.SDK.8 --accept-source-agreements --accept-package-agreements
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Winget install failed. Please install manually from:
    echo https://dotnet.microsoft.com/download/dotnet/8.0
    pause
    exit /b 1
)
echo .NET 8 SDK installed. Please restart your terminal.
pause
