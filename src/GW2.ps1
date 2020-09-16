[CmdletBinding(SupportsShouldProcess=$true)]
Param()

# Config - Change these variables to match your personal setup
$JSON = Get-Content "./config/Config.json" | Out-String | ConvertFrom-Json

[String]$GW2_EXE = $JSON.GW2_Exe
[String[]]$START_PARAMS = $JSON.Start_Params

[String]$TACO_EXE = $JSON.TacO_Exe

[Int]$DOWNLOAD_RETRIES = $JSON.Download_Retries
[Int]$STABILITY_CHECK_SECONDS = $JSON.Stability_Check_Duration_Seconds

# Program - Do not change anything beyond this point unless you know what you're doing

# Fight Bugs                      |     |
#                                 \\_V_//
#                                 \/=|=\/
#                                  [=v=]
#                                __\___/_____
#                               /..[  _____  ]
#                              /_  [ [  M /] ]
#                             /../.[ [ M /@] ]
#                            <-->[_[ [M /@/] ]
#                           /../ [.[ [ /@/ ] ]
#      _________________]\ /__/  [_[ [/@/ C] ]
#     <_________________>>0---]  [=\ \@/ C / /
#        ___      ___   ]/000o   /__\ \ C / /
#           \    /              /....\ \_/ /
#        ....\||/....           [___/=\___/
#       .    .  .    .          [...] [...]
#      .      ..      .         [___/ \___]
#      .    0 .. 0    .         <---> <--->
#   /\/\.    .  .    ./\/\      [..]   [..]
#  / / / .../|  |\... \ \ \    _[__]   [__]_
# / / /       \/       \ \ \  [____>   <____]

[String]$GW2_FOLDER = Split-Path -Path $GW2_EXE
[String]$ARC_FOLDER = Join-Path $GW2_FOLDER "bin64"
[String]$ARC_URL = "https://www.deltaconnected.com/arcdps/x64/"
[String]$ARC_MD5 = "d3d9.dll.md5sum"
[String[]]$ARC_FILES = @("d3d9.dll")

function test_config() {
    Write-Verbose "Testing Configuration..."
    try {
        if (!(Test-Path $GW2_EXE)) {
            Write-Error "GW2 executable was not found at given path `"$GW2_EXE`"."
            Read-Host
            exit -1
        }
    } catch {
        Write-Error "GW2 executable path `"$GW2_EXE`" is not a valid path."
        Read-Host
        exit -1
    }

    try {
        if (!(Test-Path $TACO_EXE)) {
            Write-Error "TACO executable was not found at given path `"$TACO_EXE`"."
            Read-Host
            exit -1
        }
    } catch {
        Write-Error "TACO executable path `"$TACO_EXE`" is not a valid path."
        Read-Host
        exit -1
    }
    Write-Verbose "Testing Configuration complete."
}

function download_as_string($uri) {
    Write-Debug "Download-Uri: $uri"
    $ans = Invoke-WebRequest -Uri $uri -UseBasicParsing
    $str = [System.Text.Encoding]::ASCII.GetString($ans.Content)
    Write-Debug "Data Received: $str"
    return $str
}

function download_to_file($uri, $path) {
    $parent_folder = Split-Path -Path $path
    if (!(Test-Path $parent_folder)) {
        New-Item -ItemType Directory -Force -Path $parent_folder
    }

    Invoke-WebRequest -Uri $uri -OutFile $path -UseBasicParsing
}

function md5($file) {
    Write-Debug "MD5-File: $file"
    $ans = Get-FileHash $file -Algorithm MD5
    Write-Debug "Generated Hash: $ans"
    return $ans.Hash
}

function update_file($file_path, $origin_md5sum, $retries) {
    if (!(Test-Path $file_path)) {
        Write-Host "Downloading file $file_path..."
        download_to_file "$ARC_URL$file" $file_path
        Write-Host "Download complete."
    }

    $md5sum = md5 $file_path
    if (!($origin_md5sum -like "*$md5sum*")) {
        Remove-Item $file_path
        Write-Host "$file_path does not match md5sum. File has been deleted."
        if ($retries -gt 0) {
            Write-Host "$retries retries left. Attempting retry..."
            update_file $file_path $origin_md5sum ($retries - 1)
        }
    } else {
        Write-Host "$file_path is up-to-date."
    }
}

function update_arc() {
    Write-Verbose "Updating Arc-Dps..."
    $origin_md5sum = download_as_string "$ARC_URL$ARC_MD5"
    # foreach ($file in $ARC_FILES) {
    #     $file_path = Join-Path $ARC_FOLDER $file
    #     update_file $file_path $origin_md5sum $DOWNLOAD_RETRIES
    # }
    Write-Verbose "Updating Arc-Dps complete."
}

function is_running($exe, $retry) {
    $process_name = [System.IO.Path]::GetFileNameWithoutExtension($exe)
    $process = Get-Process -Name $process_name -ErrorAction SilentlyContinue

    if ($process) {
        return $process
    }

    if ($retry -le 0) {
        return $process
    }

    Start-Sleep -Seconds 1
    return is_running $process_name ($retry - 1)
}

function start_gw2() {
    Write-Verbose "Starting Guild Wars 2..."

    $wdir = Split-Path -Path $GW2_EXE
    Start-Process -FilePath $GW2_EXE -WorkingDirectory $wdir -ArgumentList $START_PARAMS

    Write-Verbose "Starting Guild Wars 2 complete."
}

function start_taco() {
    Write-Verbose "Starting TacO..."

    while (!(is_running $TACO_EXE 3)) {
        if (!(is_running $GW2_EXE 3)) {
            Write-Error "Guild Wars 2 was closed unexpectedly."
            Read-Host
            exit -1
        }

        Write-Information "TacO is not running. Trying again..."

        $wdir = Split-Path -Path $TACO_EXE
        Start-Process -FilePath $TACO_EXE -WorkingDirectory $wdir

        Start-Sleep -Seconds 5
    }

    Write-Verbose "Starting TacO complete."
}

function ban_current_arc_version() {
    Write-Host "Removing current version of Arc-Dps due to stability issues."
    foreach ($file in $ARC_FILES) {
        $file_path = Join-Path $ARC_FOLDER $file
        $ban_path = $file_path + ".broke"
        $md5 = md5 $file_path

        New-Item $ban_path
        Set-Content $ban_path $md5

        Remove-Item $file_path
    }
}

function monitor_game_stability() {
    do {
        $process_name = [System.IO.Path]::GetFileNameWithoutExtension($GW2_EXE)
        $process = Get-Process -Name $process_name -ErrorAction SilentlyContinue

        $exit = $process.WaitForExit($STABILITY_CHECK_SECONDS * 1000)
        if ($exit) {
            $error_message = Get-Process -ErrorAction SilentlyContinue "rundll32" | Where-Object {$_.MainWindowTitle -like "Fehler"}
            if ($error_message) {
                Write-Verbose "Found error message."
            } else {
                Write-Verbose "No error message."
            }
        }
    } while (is_running($GW2_EXE, 3))
}

function main() {
    test_config
    update_arc
    start_gw2
    start_taco
    monitor_game_stability
    exit 0
}

main
