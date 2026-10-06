[CmdletBinding()]
param(
    [ValidateSet('Press','KeyDown','KeyUp','Hold')][string]$Action,
    [switch]$Probe,
    [switch]$ListCandidateWindows,
    [string]$Key,
    [string]$RunId,
    [int]$HoldMilliseconds = 3000,
    [string]$ScreenshotPath,
    [switch]$CaptureOnly
)

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
. (Join-Path $PSScriptRoot 'lib\window-discovery.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CmQaNative {
  public sealed class WindowInfo {
    public long Hwnd;
    public bool Visible;
    public bool Minimized;
    public string Title;
    public string ClassName;
    public int ProcessId;
    public int Left;
    public int Top;
    public int Width;
    public int Height;
    public int ClientWidth;
    public int ClientHeight;
  }
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)] private struct KEYBDINPUT { public ushort Vk; public ushort Scan; public uint Flags; public uint Time; public UIntPtr ExtraInfo; }
  [StructLayout(LayoutKind.Explicit, Size=40)] private struct INPUT {
    [FieldOffset(0)] public uint Type;
    [FieldOffset(8)] public KEYBDINPUT Keyboard;
  }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int command);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint attach, uint attachTo, bool attachInput);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
  [DllImport("user32.dll")] private static extern uint SendInput(uint count, INPUT[] inputs, int size);

  public static WindowInfo[] EnumerateWindows() {
    var rows = new List<WindowInfo>();
    EnumWindows((hWnd, lParam) => {
      var title = new StringBuilder(512);
      var className = new StringBuilder(256);
      GetWindowText(hWnd, title, title.Capacity);
      GetClassName(hWnd, className, className.Capacity);
      RECT outer; RECT client; uint processId;
      if (!GetWindowRect(hWnd, out outer)) return true;
      GetClientRect(hWnd, out client);
      GetWindowThreadProcessId(hWnd, out processId);
      rows.Add(new WindowInfo {
        Hwnd = hWnd.ToInt64(), Visible = IsWindowVisible(hWnd), Minimized = IsIconic(hWnd),
        Title = title.ToString(), ClassName = className.ToString(), ProcessId = (int)processId,
        Left = outer.Left, Top = outer.Top, Width = Math.Max(0, outer.Right - outer.Left),
        Height = Math.Max(0, outer.Bottom - outer.Top), ClientWidth = Math.Max(0, client.Right - client.Left),
        ClientHeight = Math.Max(0, client.Bottom - client.Top),
      });
      return true;
    }, IntPtr.Zero);
    return rows.ToArray();
  }

  public static bool FocusWindow(long handle) {
    var hWnd = new IntPtr(handle);
    if (!IsWindow(hWnd)) return false;
    ShowWindowAsync(hWnd, 9);
    uint owningProcessId;
    var targetThread = GetWindowThreadProcessId(hWnd, out owningProcessId);
    var currentThread = GetCurrentThreadId();
    var attached = targetThread != 0 && targetThread != currentThread && AttachThreadInput(currentThread, targetThread, true);
    try { BringWindowToTop(hWnd); SetForegroundWindow(hWnd); }
    finally { if (attached) AttachThreadInput(currentThread, targetThread, false); }
    return GetForegroundWindow() == hWnd;
  }
  public static bool IsForeground(long handle) { return GetForegroundWindow() == new IntPtr(handle); }
  public static bool SendKey(byte virtualKey, bool keyUp) {
    var scan = MapVirtualKey(virtualKey, 0);
    if (scan == 0) return false;
    var input = new INPUT[1]; input[0].Type = 1;
    input[0].Keyboard = new KEYBDINPUT { Vk = 0, Scan = (ushort)scan, Flags = 0x0008u | (keyUp ? 0x0002u : 0u), Time = 0, ExtraInfo = UIntPtr.Zero };
    return SendInput(1, input, Marshal.SizeOf(typeof(INPUT))) == 1;
  }
}
'@

function Get-CmQaProcessTable {
    $table = @{}
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        $id = [int]$process.Id
        $table[$id] = [pscustomobject]@{ id=$id; name=[string]$process.ProcessName; path=''; parentId=0 }
    }
    foreach ($item in @(Get-CimInstance -ClassName Win32_Process -Filter "Name LIKE 'FiveM%'" -ErrorAction SilentlyContinue)) {
        $table[[int]$item.ProcessId] = [pscustomobject]@{ id=[int]$item.ProcessId; name=[string]$item.Name; path=[string]$item.ExecutablePath; parentId=[int]$item.ParentProcessId }
    }
    return $table
}

function Get-CmQaProcessAncestry([hashtable]$Table, [int]$ProcessId) {
    $result = [Collections.Generic.List[object]]::new(); $seen = @{}; $current = $ProcessId
    for ($i = 0; $i -lt 8 -and $current -gt 0 -and -not $seen.ContainsKey($current); $i++) {
        $seen[$current] = $true; if (-not $Table.ContainsKey($current)) { break }
        $item = $Table[$current]; $result.Add($item); $current = [int]$item.parentId
    }
    return @($result)
}

function Test-CmQaFiveMName([string]$Name) {
    if (-not $Name) { return $false }
    if ($Name -match '^(?i)FiveM_(ChromeBrowser|DumpServer|ROSLauncher|ROSService)$') { return $false }
    return $Name -match '^(?i)FiveM(?:$|_)'
}

function Test-CmQaFiveMProcess([object]$ProcessInfo) {
    if ($null -eq $ProcessInfo) { return $false }
    if ([string]$ProcessInfo.name -match '^(?i)(cmd|powershell|pwsh|conhost|WindowsTerminal|Code|msedge|chrome)(\.exe)?$') { return $false }
    if (Test-CmQaFiveMName ([string]$ProcessInfo.name)) { return $true }
    return [string]$ProcessInfo.path -match '(?i)\\FiveM(?:\.app)?\\'
}

function Get-CmQaWindowSelection {
    $table = Get-CmQaProcessTable; $observed = [Collections.Generic.List[object]]::new()
    $windows = @([CmQaNative]::EnumerateWindows())
    $recoverable = @($windows | Where-Object {
        $process = if ($table.ContainsKey([int]$_.ProcessId)) { $table[[int]$_.ProcessId] } else { $null }
        (Test-CmQaFiveMProcess $process) -and
        ([string]$process.name -match '^(?i)FiveM(?:_[^_]+)?_GTAProcess(?:\.exe)?$|^FiveM_GTAProcess(?:\.exe)?$') -and
        ([string]$_.ClassName -match '^(?i)grcWindow$') -and
        ($_.Minimized -or [int]$_.ClientWidth -lt 320 -or [int]$_.ClientHeight -lt 200)
    })
    foreach ($window in $recoverable) { [void][CmQaNative]::ShowWindowAsync([IntPtr]([int64]$window.Hwnd), 9) }
    if ($recoverable.Count -gt 0) { Start-Sleep -Milliseconds 250; $windows = @([CmQaNative]::EnumerateWindows()) }
    foreach ($window in $windows) {
        $process = if ($table.ContainsKey([int]$window.ProcessId)) { $table[[int]$window.ProcessId] } else { $null }
        $ancestry = Get-CmQaProcessAncestry $table ([int]$window.ProcessId)
        $directFamily = Test-CmQaFiveMProcess $process
        $ancestorFamily = @($ancestry | Where-Object { Test-CmQaFiveMProcess $_ }).Count -gt 1
        $name = if ($process) { [string]$process.name } else { '' }
        $isChromeHelper = $name -match '^(?i)FiveM_ChromeBrowser$|^(?i)(chrome|msedge)$' -or [string]$window.ClassName -match '^(?i)(Chrome_WidgetWin|CEF)'
        $isConsole = $name -match '^(?i)(conhost|cmd|powershell|pwsh|WindowsTerminal)$' -or [string]$window.ClassName -match '^(?i)ConsoleWindowClass$'
        $isRenderer = $name -match '^(?i)FiveM(?:_[^_]+)?_GTAProcess(?:\.exe)?$|^FiveM_GTAProcess(?:\.exe)?$'
        $rendererClass = [string]$window.ClassName -match '^(?i)(grcWindow|GLFW|SDL_app|UnityWndClass)$'
        $rendererTitle = [string]$window.Title -match '(?i)FiveM|Grand Theft Auto|GTA'
        $score = 0; $reasons = [Collections.Generic.List[string]]::new()
        if ($isRenderer) { $score += 100; $reasons.Add('confirmed_fivem_gta_process') }
        elseif ($directFamily) { $score += 35; $reasons.Add('fivem_process_family') }
        elseif ($ancestorFamily) { $score += 25; $reasons.Add('fivem_process_ancestry') }
        if ($window.Visible) { $score += 20; $reasons.Add('visible_top_level_window') }
        if ([int]$window.ClientWidth -ge 320 -and [int]$window.ClientHeight -ge 200) { $score += 20; $reasons.Add('meaningful_client_area') }
        if ($rendererClass) { $score += 15; $reasons.Add('renderer_window_class') }
        if ($rendererTitle) { $score += 5; $reasons.Add('renderer_like_title') }
        $accepted = ($directFamily -or $ancestorFamily) -and $window.Visible -and -not $isChromeHelper -and -not $isConsole -and [int]$window.ClientWidth -ge 320 -and [int]$window.ClientHeight -ge 200 -and ($isRenderer -or $rendererClass -or ($rendererTitle -and $name -notmatch '^(?i)FiveM$'))
        $rejectReason = if ($isChromeHelper) { 'cef_or_browser_helper' } elseif ($isConsole) { 'console_or_shell_window' } elseif (-not $window.Visible) { 'hidden_window' } elseif ([int]$window.ClientWidth -lt 320 -or [int]$window.ClientHeight -lt 200) { 'zero_or_nonmeaningful_client_area' } elseif (-not ($directFamily -or $ancestorFamily)) { 'not_fivem_process_family' } elseif (-not ($isRenderer -or $rendererClass -or $rendererTitle)) { 'not_renderer_like' } else { $null }
        $observed.Add([pscustomobject][ordered]@{ hwnd=('0x{0:X}' -f [int64]$window.Hwnd); hwndValue=[int64]$window.Hwnd; title=[string]$window.Title; class=[string]$window.ClassName; pid=[int]$window.ProcessId; process=$name; visible=[bool]$window.Visible; minimized=[bool]$window.Minimized; score=[int]$score; reason=if($accepted){$reasons -join ','}else{$rejectReason}; accepted=[bool]$accepted; left=[int]$window.Left; top=[int]$window.Top; width=[int]$window.Width; height=[int]$window.Height; clientWidth=[int]$window.ClientWidth; clientHeight=[int]$window.ClientHeight })
    }
    $selection = Select-CmQaWindowCandidate @($observed)
    return [pscustomobject]@{ status=[string]$selection.status; selected=$selection.selected; candidates=@($selection.candidates); observed=@($observed); processTable=$table }
}

function Write-CmQaWindowProbe([object]$Selection, [switch]$PrintDetails) {
    $path = Join-Path (Get-CmQaOutputRoot) 'client-window-probe.json'
    $evidence = [ordered]@{ generatedAt=(Get-Date).ToUniversalTime().ToString('o'); result=$Selection.status; selected=if($Selection.selected){$Selection.selected}else{$null}; candidates=@($Selection.candidates); observedWindows=@($Selection.observed) }
    Write-CmQaJson $path $evidence
    if ($PrintDetails) {
        Write-Output ('CLIENT_WINDOW_PROBE ' + ($evidence | ConvertTo-Json -Compress -Depth 12))
    } else {
        $selected = if ($Selection.selected) { '{0} pid={1} process={2}' -f $Selection.selected.hwnd,$Selection.selected.pid,$Selection.selected.process } else { 'none' }
        Write-Output ('CLIENT_WINDOW_PROBE result={0} selected={1}' -f $Selection.status,$selected)
    }
    Write-Output ('CLIENT_WINDOW_PROBE_PATH=' + $path)
}

function Get-CmQaSelectedWindow([object]$Selection) {
    if ($Selection.status -ne 'CLIENT_WINDOW_FOUND' -or $null -eq $Selection.selected) { throw ('CLIENT_DRIVER_BLOCKED: ' + $Selection.status) }
    $selected = $Selection.selected
    $current = @($Selection.observed | Where-Object { [int64]$_.hwndValue -eq [int64]$selected.hwndValue } | Select-Object -First 1)
    if ($current.Count -ne 1 -or $current[0].accepted -ne $true) { throw 'CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_STALE' }
    if (-not [CmQaNative]::IsWindow([IntPtr]([int64]$selected.hwndValue))) { throw 'CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_STALE' }
    return $selected
}

function Assert-CmQaWindowFocused([object]$Selected) {
    $handle = [int64]$Selected.hwndValue
    if (-not [CmQaNative]::IsWindow([IntPtr]$handle)) { throw 'CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_STALE' }
    if (-not [CmQaNative]::IsWindowVisible([IntPtr]$handle)) { throw 'CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_NOT_VISIBLE' }
    $process = Get-Process -Id ([int]$Selected.pid) -ErrorAction SilentlyContinue
    if (-not $process -or -not (Test-CmQaFiveMProcess ([pscustomobject]@{ name=[string]$process.ProcessName; path=''; parentId=0 }))) { throw 'CLIENT_DRIVER_BLOCKED_FIVEM_PROCESS_STALE' }
    if (-not [CmQaNative]::IsForeground($handle)) { throw 'CLIENT_DRIVER_BLOCKED_FOCUS_FAILED' }
}

function Focus-CmQaWindow([object]$Selected) {
    $handle = [int64]$Selected.hwndValue
    if (-not [CmQaNative]::FocusWindow($handle)) { throw 'CLIENT_DRIVER_BLOCKED_FOCUS_FAILED' }
    Start-Sleep -Milliseconds 150; Assert-CmQaWindowFocused $Selected
    Write-Output ('CLIENT_WINDOW_FOUND hwnd={0} pid={1} process={2} title={3}' -f $Selected.hwnd,$Selected.pid,$Selected.process,$Selected.title)
    Write-Output 'FOCUS_CONFIRMED'
}

function Save-CmQaClientScreenshot([object]$Selected, [string]$Path) {
    if (-not $Path) { return }
    Assert-CmQaWindowFocused $Selected
    $left=[int]$Selected.left; $top=[int]$Selected.top; $width=[int]$Selected.width; $height=[int]$Selected.height
    if ($width -lt 1 -or $height -lt 1) { throw 'CLIENT_DRIVER_BLOCKED_SCREENSHOT_RECT_INVALID' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Add-Type -AssemblyName System.Drawing
    $bitmap=[System.Drawing.Bitmap]::new($width,$height); $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
    try { $graphics.CopyFromScreen($left,$top,0,0,[System.Drawing.Size]::new($width,$height)); $bitmap.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
    Write-Output ('CLIENT_SCREENSHOT=' + $Path)
}

$selection = Get-CmQaWindowSelection
Write-CmQaWindowProbe $selection -PrintDetails:($Probe -or $ListCandidateWindows)
if ($Probe -or $ListCandidateWindows) { if ($selection.status -ne 'CLIENT_WINDOW_FOUND') { exit 2 }; exit 0 }

$safety=Test-CmQaRuntimeSafety; if (-not $safety.ok) { throw "CLIENT_DRIVER_BLOCKED: $($safety.reason)" }
$missingAction = -not $Action -or -not $Key -or -not $RunId
if ($missingAction) { throw 'CLIENT_DRIVER_BLOCKED: Action, Key, and RunId are required for physical input.' }
$marker=Join-Path (Get-CmQaRunDirectory $RunId) 'client-active.json'
if (-not (Test-Path -LiteralPath $marker)) { throw 'CLIENT_DRIVER_BLOCKED: QA run is not active.' }
$markerState=Get-Content -Raw -LiteralPath $marker | ConvertFrom-Json
if ($markerState.active -ne $true) { throw 'CLIENT_DRIVER_BLOCKED: QA run marker is inactive.' }
$send=Join-Path $PSScriptRoot '..\cm-runtime\send-command.ps1'
$serverStatus=Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$send,'cm_qa_status')
if ($serverStatus.result -ne 'PASS' -or ($serverStatus.output -notmatch '"activeClient"\s*:\s*\{' -and -not $CaptureOnly)) { throw 'CLIENT_DRIVER_BLOCKED: server has no active QA client run.' }

$selected=Get-CmQaSelectedWindow $selection; Focus-CmQaWindow $selected
$virtualKeys=@{ 'ESC'=0x1B; 'ENTER'=0x0D; 'SPACE'=0x20; 'E'=0x45; 'G'=0x47; 'W'=0x57; 'A'=0x41; 'S'=0x53; 'D'=0x44; 'F6'=0x75; 'F9'=0x78 }
$normalized=$Key.ToUpperInvariant(); if (-not $virtualKeys.ContainsKey($normalized)) { throw "CLIENT_DRIVER_BLOCKED: unsupported safe key '$Key'." }
$vk=[byte]$virtualKeys[$normalized]
if ($CaptureOnly) { Save-CmQaClientScreenshot $selected $ScreenshotPath; return }

$keyDown=$false; $completed=$false
try {
    Assert-CmQaWindowFocused $selected
    switch ($Action) {
        'Press' { if (-not [CmQaNative]::SendKey($vk,$false)) { throw 'CLIENT_DRIVER_BLOCKED_SENDINPUT_FAILED' }; $keyDown=$true; Start-Sleep -Milliseconds 40; Assert-CmQaWindowFocused $selected; if (-not [CmQaNative]::SendKey($vk,$true)) { throw 'CLIENT_DRIVER_BLOCKED_SENDINPUT_KEYUP_FAILED' }; $keyDown=$false }
        'KeyDown' { if (-not [CmQaNative]::SendKey($vk,$false)) { throw 'CLIENT_DRIVER_BLOCKED_SENDINPUT_FAILED' }; $keyDown=$true }
        'KeyUp' { if (-not [CmQaNative]::SendKey($vk,$true)) { throw 'CLIENT_DRIVER_BLOCKED_SENDINPUT_KEYUP_FAILED' } }
        'Hold' {
            if ($HoldMilliseconds -lt 1 -or $HoldMilliseconds -gt 10000) { throw 'CLIENT_DRIVER_BLOCKED: HoldMilliseconds must be 1..10000.' }
            if (-not [CmQaNative]::SendKey($vk,$false)) { throw 'CLIENT_DRIVER_BLOCKED_SENDINPUT_FAILED' }; $keyDown=$true
            $started=Get-Date; $deadline=$started.AddMilliseconds($HoldMilliseconds)
            while ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 25; Assert-CmQaWindowFocused $selected }
            $measured=[int]((New-TimeSpan -Start $started -End (Get-Date)).TotalMilliseconds)
            if (-not [CmQaNative]::SendKey($vk,$true)) { throw 'CLIENT_DRIVER_BLOCKED_SENDINPUT_KEYUP_FAILED' }; $keyDown=$false
            Write-Output ('CLIENT_HOLD_MEASURED requestedHoldMs={0} clientMeasuredHoldMs={1}' -f $HoldMilliseconds,$measured)
        }
    }
    $completed=$true
} finally {
    if ($keyDown -and -not $completed) {
        try {
            if ([CmQaNative]::FocusWindow([int64]$selected.hwndValue)) {
                Assert-CmQaWindowFocused $selected
                [void][CmQaNative]::SendKey($vk,$true)
            }
        } catch { }
    }
}
Save-CmQaClientScreenshot $selected $ScreenshotPath
Write-Output ('SENDINPUT action={0} key={1} window={2}' -f $Action,$normalized,$Selected.title)
