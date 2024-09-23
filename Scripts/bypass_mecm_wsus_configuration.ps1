
# Bypass GPO or MECM configured WSUS settings.

$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

Set-ItemProperty -Path $path -Name "NoAutoUpdate" -Value 0
Set-ItemProperty -Path $path -Name "UseWUServer" -Value 0

Restart-Service wuauserv 