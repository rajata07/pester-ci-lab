# pester.config.ps1 — Solution

$config = New-PesterConfiguration

# Test discovery
$config.Run.Path = @("./tests/Unit")
$config.Run.Throw = $true

# Output
$config.Output.Verbosity = "Detailed"

# Code coverage
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @("./src/modules/NetworkHelper/NetworkHelper.psm1")
$config.CodeCoverage.CoveragePercentTarget = 80
$config.CodeCoverage.OutputFormat = "JaCoCo"
$config.CodeCoverage.OutputPath = "./TestResults/coverage.xml"

# Test results
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = "NUnit3"
$config.TestResult.OutputPath = "./TestResults/test-results.xml"

$config
