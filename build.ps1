<#
.SYNOPSIS
  Builds the project and runs the tests, optionally publishing artifacts and packages for later deployment.
.DESCRIPTION
  Builds the project and runs the tests, optionally publishing artifacts and packages for later deployment.
.PARAMETER $ArtifactsStagingPath
  If specified, the staged artifacts are placed into this folder as a temporary output storage location.
.PARAMETER $PublishArtifactsToAzureDevOps
  If $true, the build publishes artifacts to Azure DevOps by writing the necessary lines to the console output.
.PARAMETER $BuildVerbosity
  The dotnet --verbosity= value: q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].
.PARAMETER $SrcBranchName
  The source branch name e.g. "local" or "3123-issue", usually $env:BUILD_SOURCEBRANCHNAME from Azure DevOps.
.PARAMETER $BuildId
  The build ID e.g. 12345, defaults to $env:BUILD_BUILDID from Azure DevOps.
.INPUTS
  none
.OUTPUTS
  none
.EXAMPLE
  build.ps1
.EXAMPLE
  build.ps1 -ArtifactsStagingPath ./artifacts
  
  Builds and tests everything and writes the generated artifacts to a specified path.
.EXAMPLE
  build.ps1 -pubtodevops
  
  Builds and tests everything and publishes artifacts to Azure DevOps by writing the magic output lines it requires.
.EXAMPLE
  build.ps1 -BuildVerbosity normal -ArtifactsStagingPath C:\temp\artifacts-staging -PublishArtifactsToAzureDevOps
  
  Just another example using more options.
#>
Param(
    # If specified, the artifacts output into this folder
    [Parameter(Mandatory=$false, Position=1)]
    [System.IO.FileInfo]
    $ArtifactsStagingPath = "artifacts",

    # If $true, then we will write output lines so Azure DevOps takes the artifacts.
    [Parameter(Mandatory=$false, Position=2)]
    [switch]
    [Alias("pubtodevops")]
    $PublishArtifactsToAzureDevOps = $false,

    # The dotnet --verbosity= value: q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic].
    [Parameter(Mandatory=$false, Position=3)]
    [string]
    [ValidateSet("quiet", "q", "minimal", "m", "normal", "n", "detailed", "d", "diagnostic", "diag")]
    $BuildVerbosity = "minimal",

    # The source branch name e.g. "local" or "3123-issue", usually $env:BUILD_SOURCEBRANCHNAME from Azure DevOps
    [Parameter(Mandatory=$false, Position=4)]
    [string]
    $SrcBranchName = $env:BUILD_SOURCEBRANCHNAME,

    # The build ID e.g. 12345, defaults to $env:BUILD_BUILDID from Azure DevOps
    [Parameter(Mandatory=$false, Position=5)]
    [string]
    $BuildId = $env:BUILD_BUILDID
)

function Compress-Directory {
    param (
        [string]$directoryToZip
    )
    $zippedArtifactOutputFolder = [System.IO.Directory]::GetParent("$directoryToZip")
    $name = [System.IO.Path]::GetFileName($directoryToZip)
    $zipFileName = "$name.zip"
    $zippedArtifactFullFilePath = [System.IO.Path]::Combine("$zippedArtifactOutputFolder", "$zipFileName")
    Write-Host "build: zipping '$directoryToZip' into '$zippedArtifactFullFilePath'"
    Push-Location $directoryToZip
    Compress-Archive -Path "./*" -DestinationPath "$zippedArtifactFullFilePath" -Force
    Pop-Location
    return $zippedArtifactFullFilePath
}

Write-Host "build: Build started"

if ($VerbosePreference) {
    & dotnet --info
}

Push-Location $PSScriptRoot
try {
    Write-Host "build: Starting in folder '$PSScriptRoot'"
    
    if(Test-Path ./artifacts) {
        Write-Host "build: Cleaning ./artifacts"
        Remove-Item ./artifacts -Force -Recurse
    }

    $ArtifactsStagingPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ArtifactsStagingPath)
    Write-Host "build: staging artifacts to '$ArtifactsStagingPath'"
    
    $branch = @{ $true = $SrcBranchName; $false = $(git symbolic-ref --short -q HEAD) }[$SrcBranchName -ne $NULL];
    $revision = @{ $true = "{0:00000}" -f [convert]::ToInt32("0" + $BuildId, 10); $false = "lo" }[$BuildId -ne $NULL];
    $suffix = @{ $true = ""; $false = "$($branch.Substring(0, [math]::Min(10,$branch.Length)))-$revision"}[$branch -eq "master" -and $revision -ne "lo"]
    $commitHash = $(git rev-parse --short HEAD)
    $buildSuffix = @{ $true = "$($suffix)-$($commitHash)"; $false = "$($branch)-$($commitHash)" }[$suffix -ne ""]

    Write-Host "build: Package version suffix is $suffix"
    Write-Host "build: Build version suffix is $buildSuffix"

    & dotnet build "kmd-momentum-mea.sln" -c Release --verbosity "$BuildVerbosity" --version-suffix "$buildSuffix"
    if($LASTEXITCODE -ne 0) { exit 3 }

    $PublishedApplications = $(
        "Kmd.Momentum.Mea.Api"
    )

    foreach ($srcProjectName in $PublishedApplications) {
        Push-Location "./src/$srcProjectName"
        try {
            Write-Host "build: publishing output of '$srcProjectName' into '$ArtifactsStagingPath/$srcProjectName'"

            if ($suffix) {
                & dotnet publish -c Release --verbosity "$BuildVerbosity" --no-build --no-restore -o "$ArtifactsStagingPath/$srcProjectName" --version-suffix "$suffix"
            }
            else {
                & dotnet publish -c Release --verbosity "$BuildVerbosity" --no-build --no-restore -o "$ArtifactsStagingPath/$srcProjectName"
            }
            if($LASTEXITCODE -ne 0) { exit 3 }

            $compressedArtifactFileName = Compress-Directory "$ArtifactsStagingPath/$srcProjectName"
            if ($PublishArtifactsToAzureDevOps) {
                Write-Host "##vso[artifact.upload artifactname=Applications;]$compressedArtifactFileName"
            }
        }
        finally {
            Pop-Location
        }
    }

    foreach ($testFolder in Get-ChildItem "./test/*.Tests") {
        Push-Location "$testFolder"
        try {
            Write-Host "build: Testing project in '$testFolder'"

            & dotnet test -c Release --logger trx --verbosity="$BuildVerbosity" --no-build --no-restore
            if($LASTEXITCODE -ne 0) { exit 3 }
        }
        finally {
            Pop-Location
        }
    }

    if($PublishArtifactsToAzureDevOps) {
      $deployScriptSourcePath = "$PSScriptRoot/deploy"
      $artifactsOutputPath = "$ArtifactsStagingPath/deploy"
      Write-Host "build: publishing files from '$deployScriptSourcePath' to '$artifactsOutputPath'"

      If(!(test-path $artifactsOutputPath)) {
        Write-Host "build: creating folder '$artifactsOutputPath'"
        New-Item -ItemType Directory -Force -Path $artifactsOutputPath
      }

      $resolvedArtifactsOutputPath = Resolve-Path -Path "$artifactsOutputPath"
      Copy-Item "$deployScriptSourcePath/*" -Destination $resolvedArtifactsOutputPath -Recurse
      Write-Host "##vso[artifact.upload containerfolder=deploy;artifactname=deploy;]$resolvedArtifactsOutputPath"
    }
}
finally {
    Pop-Location
}
 