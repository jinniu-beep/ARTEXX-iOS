@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================
echo   ARTEXX iOS  一键构建 IPA
echo ============================================
echo.

rem ---------- 1. 环境检查 ----------
where git >nul 2>nul || (echo [X] 没找到 git，请先安装 Git for Windows & pause & exit /b 1)
where node >nul 2>nul || (echo [X] 没找到 node，请先安装 Node.js & pause & exit /b 1)
where gh >nul 2>nul || (echo [X] 没找到 gh，请先安装 GitHub CLI & pause & exit /b 1)

gh auth status >nul 2>nul || (echo [X] gh 未登录，先执行：gh auth login & pause & exit /b 1)
echo [OK] git / node / gh 就绪

rem ---------- 2. 生成 Xcode 工程 ----------
echo.
echo [1/5] 扫描 Sources 生成 xcodeproj ...
node scripts\gen-xcodeproj.mjs || (echo [X] 生成工程失败 & pause & exit /b 1)

rem ---------- 3. 语法自检 ----------
echo.
echo [2/5] Swift 语法自检 ...
node scripts\syntaxcheck.mjs
if errorlevel 1 (echo [X] 语法自检不通过 & pause & exit /b 1)

rem ---------- 4. 提交并推送 ----------
echo.
echo [3/5] 提交并推送 ...
git add -A
git diff --cached --quiet
if errorlevel 1 (
  git commit -q -m "build: auto commit %date% %time%"
  echo     已提交本地改动
) else (
  echo     没有改动，直接推送
)
git push -q || (echo [X] 推送失败，检查网络或远程权限 & pause & exit /b 1)

rem ---------- 5. 等云端编译 ----------
echo.
echo [4/5] 等待 GitHub Actions 编译（首次排队可能 3~10 分钟）...
timeout /t 6 /nobreak >nul
for /f "usebackq delims=" %%i in (`gh run list --limit 1 --json databaseId --jq ".[0].databaseId"`) do set RUNID=%%i
echo     run id = !RUNID!
gh run watch !RUNID! --exit-status
if errorlevel 1 (
  echo [X] 编译失败，日志：
  gh run view !RUNID! --log-failed
  pause
  exit /b 1
)

rem ---------- 6. 下载产物 ----------
echo.
echo [5/5] 下载 ipa ...
if exist dist rmdir /s /q dist
mkdir dist
gh run download !RUNID! -n ARTEXX-ipa -D dist || (echo [X] 下载失败 & pause & exit /b 1)

echo.
echo ============================================
echo   完成
echo ============================================
for %%f in (dist\*.ipa) do (
  echo   产物: %%~ff
  echo   大小: %%~zf 字节
)
echo.
echo 下一步：用 Sideloadly / AltStore 拖入 ipa，填 Apple ID 自签即可安装。
echo.
explorer /select,"%~dp0dist"
pause
