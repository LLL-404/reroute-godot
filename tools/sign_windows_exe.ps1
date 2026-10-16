# 导出包复签脚本（D2-1）：
#   用法：powershell -ExecutionPolicy Bypass -File tools/sign_windows_exe.ps1 -ExePath export/game.exe
#   取自本机证书库 Cert:\CurrentUser\My 的自签代码签名证书（CN=Reroute）签名导出 exe；
#   证书材料在仓外 D:\G\game\keystores\（reroute-codesign.pfx/.cer），说明见方案 §11.12。
#   每次 --export-release 重新出包后都要跑一次（game.pck 无需签名）。
param(
    [Parameter(Mandatory = $true)][string]$ExePath
)

$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Subject -eq "CN=Reroute" } | Select-Object -First 1
if (-not $cert) {
    Write-Error "CodeSign cert CN=Reroute not found in Cert:\CurrentUser\My. Restore materials from D:\G\game\keystores\reroute-codesign.pfx"
    exit 1
}
Set-AuthenticodeSignature -FilePath $ExePath -Certificate $cert | Out-Null
$sig = Get-AuthenticodeSignature -FilePath $ExePath
Write-Output ("SIGNED=" + $sig.Status)
if ($sig.Status -ne "Valid") { exit 2 }
