@echo off
cd /d "%~dp0"
dotnet test Tests\Clausage.Tests.csproj -v normal
pause
