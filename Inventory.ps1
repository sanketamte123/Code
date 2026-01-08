# ===============================
# GitHub Configuration
# ===============================
$GitHubOwner = "sanketamte123"
$RepoName    = "Inventory"
$Token       = "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"  # Hardcoded PAT
$Computer    = $env:COMPUTERNAME
$FileName    = "inventory_$Computer.csv"

# ===============================
# Manual input prompts
# ===============================
$Name       = Read-Host "Enter your Name"
$Location   = Read-Host "Enter your Location"
$Department = Read-Host "Enter your Department"

# ===============================
# Collect Inventory
# ===============================
try {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1

    # Get C: and D: drives
    $diskC = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $diskD = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'"

    $inventory = [PSCustomObject]@{
        Name         = $Name
        Location     = $Location
        Department   = $Department
        ComputerName = $Computer
        UserName     = $cs.UserName
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        SerialNumber = $bios.SerialNumber
        CPU          = $cpu.Name
        RAM_GB       = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        C_Total_GB   = if ($diskC) { [math]::Round($diskC.Size/1GB,2) } else { "" }
        C_Free_GB    = if ($diskC) { [math]::Round($diskC.FreeSpace/1GB,2) } else { "" }
        D_Total_GB   = if ($diskD) { [math]::Round($diskD.Size/1GB,2) } else { "" }
        D_Free_GB    = if ($diskD) { [math]::Round($diskD.FreeSpace/1GB,2) } else { "" }
        OS           = $os.Caption
        OSVersion    = $os.Version
        LastBootTime = $os.LastBootUpTime
        ScanDate     = Get-Date
    }

} catch {
    Write-Host "Failed to collect inventory: $_" -ForegroundColor Red
    exit
}

# ===============================
# Convert to CSV and Base64
# ===============================
$tempFile = "$env:TEMP\$FileName"
$inventory | Export-Csv $tempFile -NoTypeInformation -Force
$content = Get-Content $tempFile -Raw
$base64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))

# ===============================
# GitHub API Headers
# ===============================
$uri = "https://api.github.com/repos/$GitHubOwner/$RepoName/contents/$FileName"
$headers = @{
    Authorization = "token $Token"
    "User-Agent"  = "PowerShell-Inventory"
}

# ===============================
# Check if file exists on GitHub
# ===============================
$sha = $null
try {
    $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop -TimeoutSec 10
    if ($resp -and $resp.sha) {
        $sha = $resp.sha
        Write-Host "File exists on GitHub. Will update..."
    }
} catch {
    Write-Host "File does not exist. Will create new..."
}

# ===============================
# Prepare JSON Body for PUT
# ===============================
$body = @{
    message = "Inventory upload from $Computer"
    content = $base64
}
if ($sha) { $body["sha"] = $sha }

$bodyJson = $body | ConvertTo-Json -Depth 2

# ===============================
# Upload / Update to GitHub
# ===============================
try {
    $response = Invoke-RestMethod -Method PUT -Uri $uri -Headers $headers -Body $bodyJson -TimeoutSec 15 -ErrorAction Stop
    Write-Host "✅ Inventory uploaded successfully for $Computer"
} catch {
    Write-Host "❌ Failed to upload inventory:"
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $respText = $reader.ReadToEnd()
        Write-Host $respText -ForegroundColor Red
    } else {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}
