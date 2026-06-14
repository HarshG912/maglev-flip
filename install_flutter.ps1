Write-Host "Cloning Flutter SDK to E:\flutter with depth 1..."
git clone --depth 1 -b stable https://github.com/flutter/flutter.git E:\flutter

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to clone Flutter SDK."
    exit $LASTEXITCODE
}

Write-Host "Updating User PATH..."
$oldPath = [Environment]::GetEnvironmentVariable("Path", "User")
$flutterPath = "E:\flutter\bin"

if ($oldPath -notmatch [regex]::Escape($flutterPath)) {
    if ($oldPath -match ";$") {
        $newPath = $oldPath + $flutterPath
    } else {
        $newPath = $oldPath + ";" + $flutterPath
    }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Successfully added $flutterPath to User PATH."
} else {
    Write-Host "$flutterPath is already in User PATH."
}

$env:Path = $env:Path + ";" + $flutterPath

Write-Host "Initializing Flutter and downloading Dart SDK..."
& E:\flutter\bin\flutter.bat doctor

Write-Host "Installation script completed!"
