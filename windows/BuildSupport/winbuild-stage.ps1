. ((Split-Path -Parent $MyInvocation.MyCommand.Path) + "\winbuild-utils.ps1")

# God Check - If there's no installer something has gone wrong & error checking needs tightening up!
if (!(Test-Path -Path ".\msi-installer\iso\windows\setup.exe"))
{
	Write-Host ("Error: Failed to create the installer")
	ExitWithCode -exitcode $global:failure
}

$args | Foreach-Object {$argtable = @{}} {if ($_ -Match "(.*)=(.*)") {$argtable[$matches[1]] = $matches[2];}}
$OutDir = $argtable["OutDir"]
$zip = "${env:programfiles}\7-zip\7z.exe"
if (!(Test-Path -Path ("$zip") -PathType Leaf))
{
    Write-Host "7-zip not found at $zip, assuming 32-bit install on 64-bit Windows"
    $zip = "${env:programfiles(x86)}\7-zip\7z.exe"
}

#Create output directory
New-Item -Path $outdir -Type Directory -Force > $null
Write-Host ("Created output directory: " + $outdir) 

# Zip some bad boys up
Write-Host "Zipping up xc-windows build."
& "$zip" a -bd "$OutDir\xc-windows.zip" xc-windows 2>&1
if (!(Test-Path -Path ($outdir + "\xc-windows.zip") -PathType Leaf))
{
	Write-Host "Warning: Check for xc-windows.zip failed. But it's not build vital so carry on..."
}

Push-Location -Path "msi-installer\iso"
Write-Host "Zipping up xctools-iso directory."
& "$zip" a -bd "..\..\$OutDir\xctools-iso.zip" . 2>&1
Pop-Location
if (!(Test-Path -Path ($outdir + "\xctools-iso.zip") -PathType Leaf))
{
	Write-Host "Error: Check for xctools-iso.zip failed. Build unsuccessful."
	ExitWithCode -exitcode $global:failure
}

# Create an ISO if genisoimage is available
if (Get-Command "genisoimage.exe" -ErrorAction SilentlyContinue) 
{
	Write-Host "Creating Windows tools ISO."
	Push-Location -Path "msi-installer\iso"
	& genisoimage -R -J -joliet-long -input-charset utf-8 -quiet -o "..\..\$Outdir\xc-wintools.iso" -V "OpenXT-wintools" . 2>&1
	Pop-Location
	if (!(Test-Path -Path ($outdir + "\xc-wintools.iso") -PathType Leaf))
	{
		Write-Host "Error: Check for xc-wintools.iso failed. Build unsuccessful."
		ExitWithCode -exitcode $global:failure
	}
}

Write-Host ("Completed " + $cmdinv)
ExitWithCode -exitcode $global:success
