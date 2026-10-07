@echo off
cd /d "%~dp0"
call npm.cmd ci
if errorlevel 1 goto finish
call npm.cmd run build
if errorlevel 1 goto finish
call node_modules\.bin\wrangler.cmd login --scopes account:read user:read workers:write workers_scripts:write
if errorlevel 1 goto finish
call node_modules\.bin\wrangler.cmd deploy
:finish
pause
