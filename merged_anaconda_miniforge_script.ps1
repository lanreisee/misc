
# Merged Script: Windows Anaconda Removal and Miniforge Setup
# -----------------------------------------------------------
# This script combines the Anaconda removal and Miniforge installation functionalities.

# Part 1: Anaconda Removal
# Check if Conda is accessible
function Check-CondaInstalled {
    try {
        conda --version | Out-Null
        Log-Message "Conda is available in the system PATH."
        return $true
    } catch {
        Log-Error "Conda is not added to the system PATH. Please add Conda to the PATH and try again."
        return $false
    }
}

# Logging Functions
function Log-Message {
    param ([string]$message)
    Write-Host $message
    Add-Content $logFilePath $message
}

function Log-Error {
    param ([string]$message)
    Write-Host "ERROR: $message" -ForegroundColor Red
    Add-Content $logFilePath "ERROR: $message"
}

# Define Backup Locations
$backupLocation = "$env:USERPROFILE\conda_pkgs_backup"
$envBackupFolder = "$backupLocation\envs"
$logFilePath = "$env:TEMP\CondaBackupLog.txt"

# Verify if Conda is Accessible
if (-not (Check-CondaInstalled)) {
    exit
}

# Ensure Backup Directories Exist
if (-not (Test-Path $backupLocation)) {
    New-Item -ItemType Directory -Path $backupLocation | Out-Null
}
if (-not (Test-Path $envBackupFolder)) {
    New-Item -ItemType Directory -Path $envBackupFolder | Out-Null
}

# Determine Conda Environment Paths
$condaEnvPaths = @(
    "$env:USERPROFILE\Anaconda3\envs",
    "$env:LOCALAPPDATA\anaconda3\envs"
)

$condaEnvPath = $null
foreach ($path in $condaEnvPaths) {
    if (Test-Path $path) {
        $condaEnvPath = $path
        break
    }
}

if (-not $condaEnvPath) {
    Log-Error "Unable to determine the Conda environments path. Exiting..."
    exit
}

# Backup Conda Configuration Files
Log-Message "Backing up Conda configuration files..."
if (Test-Path "$env:USERPROFILE\.condarc") {
    Copy-Item "$env:USERPROFILE\.condarc" "$backupLocation\condarc"
} else {
    Log-Error ".condarc file not found."
}

if (Test-Path "$env:USERPROFILE\.anaconda") {
    Copy-Item "$env:USERPROFILE\.anaconda" "$backupLocation\anaconda"
} else {
    Log-Error ".anaconda folder not found."
}

# Backup Conda Channel List
try {
    Log-Message "Backing up Conda channels..."
    conda config --show channels > "$backupLocation\conda_channels_backup.txt"
    Log-Message "Conda channels backed up."
} catch {
    Log-Error "Failed to backup Conda channels."
}

# List and Log All Conda Environments
try {
    Log-Message "Listing all Conda environments..."
    $envList = conda env list | Out-String
    Log-Message "Conda environments list: $envList"
} catch {
    Log-Error "Failed to retrieve Conda environments list."
    exit
}

# Export Each Environment Individually
$environments = conda env list | Select-String -Pattern "^[^\#]" | ForEach-Object { ($_ -split '\s+')[0] }
foreach ($env in $environments) {
    try {
        Log-Message "Exporting environment $env..."
        conda env export --name $env > "$envBackupFolder\$env-environment.yml"
        Log-Message "Environment $env exported successfully."
    } catch {
        Log-Error "Failed to export environment $env. Copying environment folder as fallback..."
        $envPath = "$condaEnvPath\$env"
        if (Test-Path $envPath) {
            Copy-Item -Recurse -Force $envPath "$envBackupFolder\$env"
            Log-Message "Environment $env copied successfully."
        } else {
            Log-Error "Environment folder $env not found at $envPath."
        }
    }
}

# Final Bulk Copy of Conda Environments
try {
    Log-Message "Copying entire Conda environments folder as a final backup..."
    Copy-Item -Path $condaEnvPath -Destination $envBackupFolder -Recurse -Force
    Log-Message "Conda environments bulk backup completed successfully."
} catch {
    Log-Error "Failed to perform bulk backup of Conda environments: $_"
}

Log-Message "Backup process completed successfully."


# Part 2: Miniforge Installation and Configuration
# Set up logging with StreamWriter
$logFilePath = "$env:TEMP\MiniforgeMigrationLog.txt"

# Create StreamWriter to handle file writing
$streamWriter = [System.IO.StreamWriter]::new($logFilePath, $true)

function Log-Message {
    param ([string]$message)
    Write-Host $message
    $streamWriter.WriteLine($message)
    $streamWriter.Flush()
}

function Log-Error {
    param ([string]$errorMessage)
    Write-Host "ERROR: $errorMessage" -ForegroundColor Red
    $streamWriter.WriteLine("ERROR: $errorMessage")
    $streamWriter.Flush()
}

# Helper function to find Conda installation
function Find-CondaPath {
    $possiblePaths = @(
        "$env:USERPROFILE\Anaconda3",
        "$env:LOCALAPPDATA\anaconda3",
        "$env:USERPROFILE\Miniforge3"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

# Check if Conda is in PATH
function Is-CondaInPath {
    return ($env:Path -like "*conda*")
}

# Try-Catch block to handle failures
try {
    # Step 1: Locate Conda installation
    $condaPath = Find-CondaPath
    if ($condaPath) {
        Log-Message "Conda installation found at $condaPath."
    } else {
        Log-Error "No Conda installation found in standard directories. Exiting script."
        exit 1
    }

    # Step 2: Check if Conda is in the PATH
    if (-not (Is-CondaInPath)) {
        Log-Error "Conda is not found in the system PATH. Please add Conda to the PATH and try again."
        exit 1
    } else {
        Log-Message "Conda is available in the PATH."
    }

    # Deactivate any active Conda environments
    try {
        Log-Message "Deactivating any active Conda environments..."
        conda deactivate
    } catch {
        Log-Error "Failed to deactivate Conda environment: $_"
        exit 1
    }

    # Step 3: Remove existing Conda installation
    Log-Message "Removing Conda directory at $condaPath..."
    Remove-Item -Recurse -Force $condaPath
    Log-Message "Conda directory removed."

    # Step 4: Clean up leftover configuration files
    $condaConfigPath = "$env:USERPROFILE\.conda"
    $anacondaConfigPath = "$env:USERPROFILE\.anaconda"

    if (Test-Path $condaConfigPath) {
        Remove-Item -Recurse -Force $condaConfigPath
        Log-Message "Conda config removed."
    }

    if (Test-Path $anacondaConfigPath) {
        Remove-Item -Recurse -Force $anacondaConfigPath
        Log-Message "Anaconda config removed."
    }

    # Remove Conda from PATH
    $env:Path = $env:Path -replace [regex]::Escape("$condaPath;")
    [Environment]::SetEnvironmentVariable("Path", $env:Path, [EnvironmentVariableTarget]::User)
    Log-Message "Conda removed from PATH."

    # Step 5: Download and Install Miniforge
    Log-Message "Downloading and installing Miniforge..."
    $miniforgeURL = "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe"
    $installerPath = "$env:TEMP\Miniforge3-Windows-x86_64.exe"

    # Download the Miniforge installer
    Invoke-WebRequest -Uri $miniforgeURL -OutFile $installerPath
    Log-Message "Miniforge installer downloaded."

    # Install Miniforge silently
    Start-Process -FilePath $installerPath -ArgumentList "/InstallationType=JustMe /AddToPath=1 /RegisterPython=1 /S" -Wait
    Log-Message "Miniforge installed successfully."

    # Step 6: Initialize Conda
    $miniforgePath = "$env:USERPROFILE\Miniforge3\Scripts\conda.exe"
    if (Test-Path $miniforgePath) {
        Log-Message "Initializing Conda for PowerShell..."
        & $miniforgePath init powershell
        Log-Message "Conda initialized for PowerShell."
    } else {
        Log-Error "Conda executable not found after Miniforge installation."
        exit 1
    }

    # Step 7: Manage Conda Channels
    Log-Message "Managing Conda channels..."
    conda config --remove channels defaults
    Log-Message "Default Conda channels removed."
    conda config --add channels conda-forge
    Log-Message "conda-forge channel added."

    # Step 8: Restore Channels from Backup
    $backupFolder = "$env:USERPROFILE\Documents\Backup"
    if (Test-Path "$backupFolder\conda_channels_backup.txt") {
        $channelsBackup = Get-Content "$backupFolder\conda_channels_backup.txt"
        foreach ($channel in $channelsBackup) {
            conda config --add channels $channel
            Log-Message "Channel added: $channel"
        }
    } else {
        Log-Message "No backup file for channels found."
    }

} catch {
    Log-Error "An error occurred: $_"
    exit 1
} finally {
    $streamWriter.Close()
    Write-Host "Log file saved at $logFilePath"
}

