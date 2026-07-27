# create-disks.ps1
# Run ONCE manually from the same folder as Vagrantfile, BEFORE first "vagrant up".

$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if (-not (Test-Path $VBoxManage)) {
    Write-Host "VBoxManage.exe not found at default path, trying PATH..."
    $VBoxManage = "VBoxManage"
}

$disks = [ordered]@{
    "sdb.vdi" = 10240
    "sdc.vdi" = 1024
    "sdd.vdi" = 1200
    "sde.vdi" = 1024
    "sdf.vdi" = 1024
}

foreach ($d in $disks.GetEnumerator()) {
    $path = Join-Path (Get-Location) $d.Name
    if (Test-Path $path) {
        Write-Host "[skip]" $d.Name "already exists"
    } else {
        Write-Host "[create]" $d.Name $d.Value "MB"
        & $VBoxManage createhd --filename $path --size $d.Value
    }
}

Write-Host ""
Write-Host "Done. Now run: vagrant up"
