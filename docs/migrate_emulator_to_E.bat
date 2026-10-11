@echo off
chcp 65001 >nul
title DevEco 模拟器迁移工具 (F:\Huawei --^> E:\Huawei)
setlocal EnableExtensions

set "SRC=F:\Huawei"
set "DST=E:\Huawei"
set "OLD=F:\Huawei_old"
set "LOGFILE=%USERPROFILE%\huawei_migrate.log"

echo ==========================================================
echo   DevEco 模拟器数据迁移 : F:\Huawei  --^>  E:\Huawei
echo   脚本位置: docs\migrate_emulator_to_E.bat
echo ==========================================================
echo.

rem ---------- 0. 前置检查 ----------
for %%P in (devecostudio64.exe hvd.exe qemu-system-x86_64.exe) do (
    tasklist /FI "IMAGENAME eq %%P" 2>nul | find /I "%%P" >nul
    if not ERRORLEVEL 1 (
        echo [中止] 检测到 %%P 仍在运行，请先完全关闭后重新运行本脚本。
        goto :fail
    )
)
if not exist "%SRC%\Sdk\" (
    echo [中止] 未找到 %SRC%\Sdk。若已迁移过，请勿重复运行本脚本。
    goto :fail
)
if exist "%DST%" (
    echo [中止] %DST% 已存在。若上次迁移中断，请先删除该目录后重试。
    goto :fail
)
if exist "%OLD%" (
    echo [中止] %OLD% 已存在，请先删除该目录后重试。
    goto :fail
)

echo [1/6] 复制数据到 E 盘（约 18 GB，预计 5-20 分钟，请勿关闭窗口）...
echo.
robocopy "%SRC%" "%DST%" /E /R:2 /W:5 /TEE /LOG:"%LOGFILE%"
if ERRORLEVEL 8 (
    echo.
    echo [中止] 复制失败，详见日志 %LOGFILE%。F 盘源数据未受影响，修复后可重试。
    goto :fail
)

echo.
echo [2/6] 校验文件数量与总大小...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=Get-ChildItem -LiteralPath 'F:\Huawei' -Recurse -File -Force;$d=Get-ChildItem -LiteralPath 'E:\Huawei' -Recurse -File -Force;$ss=($s|Measure-Object Length -Sum).Sum;$ds=($d|Measure-Object Length -Sum).Sum;if($s.Count -ne $d.Count -or $ss -ne $ds){Write-Host ('  [失败] 源 '+$s.Count+' 个文件/'+$ss+' 字节, 目标 '+$d.Count+' 个文件/'+$ds+' 字节');exit 1};Write-Host ('  [通过] 共 '+$d.Count+' 个文件, '+[math]::Round($ds/1GB,2)+' GB')"
if ERRORLEVEL 1 (
    echo [中止] 校验失败，F 盘源数据未受影响。请将上方信息反馈给助手排查。
    goto :fail
)

echo [3/6] 将原目录改名为 %OLD% （保留可回退）...
ren "%SRC%" Huawei_old
if ERRORLEVEL 1 (
    echo [中止] 重命名失败，文件可能被其他程序占用。请关闭相关程序后重试。
    goto :fail
)

echo [4/6] 创建兼容目录链接 F:\Huawei --^> E:\Huawei ...
mklink /J "%SRC%" "%DST%"
if ERRORLEVEL 1 (
    echo [警告] 链接创建失败，旧 qcow2 镜像的回溯路径将失效，请反馈给助手处理。
)

echo [5/6] 更新配置文件路径（原文件自动生成 .bak 备份）...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';$targets=@('F:\MigratedFolders\AppData\Local\Huawei\Emulator26.0\.emu_config','C:\Users\60138546\AppData\Roaming\Huawei\DevEcoStudio26.0\options\deviceManager.xml','C:\Users\60138546\AppData\Roaming\Huawei\DevEcoStudio26.0\options\other.xml','C:\Users\60138546\AppData\Roaming\Huawei\DevEcoStudio6.1\options\other.xml');$targets+=(Get-ChildItem -LiteralPath 'E:\Huawei\Emulator\deployed' -Recurse -Include *.ini,*.json,*.cfg -File|Select-Object -ExpandProperty FullName);$fixed=0;foreach($f in $targets){if(Test-Path -LiteralPath $f){$b=[IO.File]::ReadAllBytes($f);$hasBom=($b.Length-ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191);$c=[IO.File]::ReadAllText($f);$n=$c.Replace('F:/Huawei/','E:/Huawei/');if($n -ne $c){Copy-Item -LiteralPath $f -Destination ($f+'.bak') -Force;[IO.File]::WriteAllText($f,$n,[Text.UTF8Encoding]::new($hasBom));Write-Host ('  已更新: '+$f);$fixed++}}};$left=@(Get-ChildItem -LiteralPath 'E:\Huawei\Emulator\deployed' -Recurse -Include *.ini,*.json,*.cfg -File|Where-Object{[IO.File]::ReadAllText($_.FullName).Contains('F:/Huawei/')});if($left.Count -gt 0){Write-Host '  [警告] 以下文件仍引用 F:/Huawei :';$left|ForEach-Object{Write-Host ('    '+$_.FullName)}}else{Write-Host ('  残留检查通过, 本次共更新 '+$fixed+' 个配置文件')}"
if ERRORLEVEL 1 (
    echo [中止] 配置更新出错，请将上方信息反馈给助手。
    goto :fail
)

echo [6/6] 删除 %OLD% 释放 F 盘空间（约 18 GB，删除需 1-2 分钟）...
rd /S /Q "%OLD%"
if exist "%OLD%" (
    echo [警告] %OLD% 未删除干净，可稍后手动删除，不影响使用。
)

echo.
echo ==================== 迁移完成 ====================
echo   当前磁盘剩余空间:
powershell -NoProfile -Command "Get-PSDrive C,E,F|Format-Table Name,@{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}} -AutoSize"
echo   后续步骤:
echo     1. 启动 DevEco Studio
echo     2. 进入 Tools ^> Device Manager，启动 MatePad Pro 13 验证
echo     3. 验证通过后，可删除本脚本与日志 %LOGFILE%
echo   核对: 让助手按 docs\模拟器迁移E盘检查清单.md 逐项核对
echo =================================================
goto :done

:fail
echo.
echo ********** 迁移未完成。失败点之前的数据均安全无损 **********
echo.
pause
exit /b 1

:done
echo.
pause
exit /b 0
