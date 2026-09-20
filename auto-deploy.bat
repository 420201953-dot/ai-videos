@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title ai-videos 自动部署 poster 首帧脚本
cd /d "%~dp0"
set "PROMPTS=F:\ai-home\data\video-prompts.json"

Rem ============ Step 0: 清理代理，避免 pull/push 因代理失败 ============
git config --global --unset http.proxy >nul 2>&1
git config --global --unset https.proxy >nul 2>&1

echo.
echo ==============================================
echo   ai-videos 自动部署 poster 首帧脚本
echo ==============================================
echo.

Rem ============ Step 1: 拉取最新视频仓 ============
echo [1/5] 拉取最新视频仓 (git pull --ff-only main) ...
git pull --ff-only origin main
if errorlevel 1 (
    echo [错误] git pull 失败，请检查网络/凭证后重试
    goto :end
)

if not exist "%PROMPTS%" (
    echo [错误] 找不到提示词文件 %PROMPTS%
    goto :end
)

Rem ============ 扫描未部署的新 mp4（不在 video-prompts.json 里的） ============
set "NEWFILES="
for %%F in (s*.mp4) do (
    set "FN=%%~nF"
    set "FOUND="
    findstr /m /c:"%%F" "%PROMPTS%" >nul 2>&1 && set "FOUND=1"
    if not defined FOUND (
        if defined NEWFILES (set "NEWFILES=!NEWFILES! %%F")
        if not defined NEWFILES (set "NEWFILES=%%F")
    )
)

if not defined NEWFILES (
    echo.
    echo 没有检测到新视频。所有 s*.mp4 都已在 video-prompts.json 中。
    echo 如果确实上传了新视频，请先 git push 到 420201953-dot/ai-videos 仓，再运行本脚本。
    goto :end
)

echo 检测到以下新视频：
echo   !NEWFILES!
echo.

set "PUSHEXTRA="

Rem ============ Step 2: 对每个新视频抽 poster 首帧 ============
set "COUNT=0"
for %%F in (!NEWFILES!) do (
    call :extractone "%%F" || goto :fail
    set /a COUNT+=1
)

echo.
echo 共抽帧 !COUNT! 个 poster。
echo.

Rem ============ Step 3: commit + push poster 到视频仓 ============
echo [3/5] commit + push 视频仓 poster ...
git add posters/
git commit -m "添加 !COUNT! 张新视频首帧 poster"
if errorlevel 1 (
    echo [提示] 可能没有可提交内容或提交失败。
)

git push origin main
if errorlevel 1 (
    echo [错误] git push origin main 失败，尝试用 PAT 认证推送...
    set "PUSHURL="
    for /f "usebackq tokens=2 delims=:@" %%p in (`findstr /i /r "^https://420201953-dot" "%USERPROFILE%\.git-credentials"`) do (
        for /f "tokens=1 delims=@" %%q in ("%%p") do (
            if not defined PUSHURL set "PUSHURL=https://420201953-dot:%%q@github.com/420201953-dot/ai-videos.git"
        )
    )
    if defined PUSHURL (
        echo 使用 PAT 认证推送（隐去 token）
        for /f "usebackq tokens=2 delims=@" %%t in (`echo !PUSHURL!`) do set "MASK=****"
        git push "!PUSHURL!" main
        if errorlevel 1 (
            echo [错误] PAT 认证推送仍失败，请手动检查凭证/代理。
            goto :end
        )
    ) else (
        echo [错误] 未找到 420201953-dot 的 PAT，无法自动推送。
        echo       请手动执行: git push origin main
        goto :end
    )
)

Rem ============ Step 4: 验证 jsdelivr（mp4 + poster），404 则等 30s 重试 1 次 ============
Rem ============ Step 4: 验证 jsdelivr（mp4 + poster），404 则等 30s 重试 1 次 ============
set "OKCOUNT=0"
set "FAILCOUNT=0"
echo.
echo [4/5] 验证 jsdelivr 可达性（首次 404 会等 30s 重试 1 次）...
for %%F in (!NEWFILES!) do (
    call :verifyurl "https://cdn.jsdelivr.net/gh/420201953-dot/ai-videos@main/%%F"
    if !OK! == 1 (set /a OKCOUNT+=1) else (set /a FAILCOUNT+=1)
    call :verifyurl "https://cdn.jsdelivr.net/gh/420201953-dot/ai-videos@main/posters/%%~nF.jpg"
    if !OK! == 1 (set /a OKCOUNT+=1) else (set /a FAILCOUNT+=1)
)

echo.
echo jsdelivr 验证：OK !OKCOUNT! 项，FAIL !FAILCOUNT! 项
if !FAILCOUNT! gtr 0 (
    echo [提示] 部分资源未同步，jsdelivr 同步通常需要 1-3 分钟，稍后刷新页面即可。
)

:done
echo.
echo ==============================================
echo   自动部署流程结束
echo ==============================================
echo.
echo 重要提示：
echo   本脚本只负责 抽 poster 首帧 + 推送视频仓，不会修改 video-prompts.json。
echo   请把「标题 / 分类 / 标签 / 提示词」粘贴给 Fitten，由 Fitten 代为在
echo   F:\ai-home\data\video-prompts.json 追加记录（id=order=新视频编号 S）。
echo ==============================================
pause
exit /b 0

:extractone
set "MP4=%~1"
set "BASE=%~n1"
if not exist "posters" mkdir posters
echo [2/5] 抽取 %MP4% → posters\%BASE%.jpg 与分辨率信息...
where ffmpeg >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 ffmpeg，请确认已安装并加入 PATH
    exit /b 1
)
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name -of csv=p=0 "%MP4" 2>nul
ffmpeg -y -i "%MP4%" -vframes 1 -q:v 3 "posters\%BASE%.jpg" >nul 2>&1
if errorlevel 1 (
    echo [错误] ffmpeg 抽帧失败: %MP4%
    exit /b 1
)
if not exist "posters\%BASE%.jpg" (
    echo [错误] 未生成 posters\%BASE%.jpg
    exit /b 1
)
for %%A in ("posters\%BASE%.jpg") do echo   已生成 %%~fA (大小 %%~zA 字节)
exit /b 0

:verifyurl
set "URL=%~1"
set "OK=0"
for /f "usebackq tokens=*" %%s in (`curl -s -o nul -w "%%{http_code}" "!URL!"`) do set "CODE=%%s"
if "%CODE%"=="200" (
    set "OK=1"
    echo   [200] %URL%
) else (
    echo   [%CODE%] %URL%  -  30s 后重试...
    timeout /t 30 /nobreak >nul
    for /f "usebackq tokens=*" %%s in (`curl -s -o nul -w "%%{http_code}" "!URL!"`) do set "CODE=%%s"
    if "%CODE%"=="200" (
        set "OK=1"
        echo   [200] %URL%  (重试成功)
    ) else (
        echo   [!CODE!] %URL%  -  仍不可达（稍后手动确认）
    )
)
exit /b 0

:fail
echo.
echo [错误] 抽帧过程中出现失败，已中止。
goto :end

:end
endlocal
exit /b 0
