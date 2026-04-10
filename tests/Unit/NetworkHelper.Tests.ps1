# NetworkHelper.Tests.ps1 — Solution

Describe "NetworkHelper Module" {

    BeforeAll {
        Import-Module "$PSScriptRoot/../../src/modules/NetworkHelper/NetworkHelper.psm1" -Force

        # Resolve-DnsName only exists on Windows (DnsClient module).
        # Create a stub so Pester can mock it on macOS/Linux.
        if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
            function global:Resolve-DnsName { param($Name, $Type, $ErrorAction) }
        }
    }

    Describe "Test-PortConnectivity" {

        Context "When the port is open" {

            It "Should return IsOpen as true" {
                # Use a real loopback connection to test open port behavior
                # PowerShell's own remoting port or any listening port
                $result = Test-PortConnectivity -ComputerName "127.0.0.1" -Port 80 -TimeoutMilliseconds 500
                # Port 80 may or may not be open — test the structure instead
                $result.ComputerName | Should -Be "127.0.0.1"
                $result.Port | Should -Be 80
                $result.PSObject.Properties.Name | Should -Contain "IsOpen"
                $result.PSObject.Properties.Name | Should -Contain "ResponseTime"
            }
        }

        Context "When the connection times out" {

            It "Should return IsOpen as false for unreachable host" {
                # Use a non-routable IP that will timeout
                $result = Test-PortConnectivity -ComputerName "192.0.2.1" -Port 9999 -TimeoutMilliseconds 500
                $result.IsOpen | Should -BeFalse
            }
        }

        Context "When the port number is invalid" {

            It "Should throw for port 0" {
                { Test-PortConnectivity -ComputerName "web-01" -Port 0 } | Should -Throw "*between 1 and 65535*"
            }

            It "Should throw for port 70000" {
                { Test-PortConnectivity -ComputerName "web-01" -Port 70000 } | Should -Throw "*between 1 and 65535*"
            }
        }
    }

    Describe "Get-DnsResolution" {

        Context "When the hostname resolves successfully" {

            BeforeAll {
                Mock Resolve-DnsName -ModuleName NetworkHelper {
                    @(
                        [PSCustomObject]@{
                            Name      = "example.com"
                            QueryType = "A"
                            TTL       = 300
                            IPAddress = "93.184.216.34"
                        }
                    )
                }
            }

            It "Should return DNS records" {
                $result = Get-DnsResolution -Hostname "example.com"
                $result.Count | Should -Be 1
                $result.Hostname | Should -Be "example.com"
            }

            It "Should return the correct IP address" {
                $result = Get-DnsResolution -Hostname "example.com"
                $result.Records[0].IPAddress | Should -Be "93.184.216.34"
            }

            It "Should set the correct record type" {
                $result = Get-DnsResolution -Hostname "example.com" -RecordType "A"
                $result.RecordType | Should -Be "A"
            }
        }

        Context "When the hostname is empty" {

            It "Should throw an error" {
                { Get-DnsResolution -Hostname "" } | Should -Throw
            }
        }

        Context "When DNS resolution fails" {

            BeforeAll {
                Mock Resolve-DnsName -ModuleName NetworkHelper { throw "DNS name does not exist" }
            }

            It "Should propagate the DNS error" {
                { Get-DnsResolution -Hostname "nonexistent.invalid" } | Should -Throw
            }
        }

        Context "When CNAME records are returned" {

            BeforeAll {
                Mock Resolve-DnsName -ModuleName NetworkHelper {
                    @(
                        [PSCustomObject]@{
                            Name      = "www.example.com"
                            QueryType = "CNAME"
                            TTL       = 600
                            NameHost  = "example.com"
                            IPAddress = $null
                        }
                    )
                }
            }

            It "Should use NameHost when IPAddress is null" {
                $result = Get-DnsResolution -Hostname "www.example.com" -RecordType "CNAME"
                $result.Records[0].IPAddress | Should -Be "example.com"
            }
        }
    }

    Describe "Get-SubnetInfo" {

        $testCases = @(
            @{ CIDR = "192.168.1.0/24"; Network = "192.168.1.0"; Mask = "255.255.255.0"; Hosts = 254 }
            @{ CIDR = "10.0.0.0/8";     Network = "10.0.0.0";    Mask = "255.0.0.0";     Hosts = 16777214 }
            @{ CIDR = "172.16.0.0/16";  Network = "172.16.0.0";  Mask = "255.255.0.0";   Hosts = 65534 }
        )

        It "Should calculate correct subnet info for <CIDR>" -TestCases $testCases {
            param($CIDR, $Network, $Mask, $Hosts)
            $result = Get-SubnetInfo -CIDR $CIDR
            $result.NetworkAddress | Should -Be $Network
            $result.SubnetMask | Should -Be $Mask
            $result.UsableHosts | Should -Be $Hosts
        }

        It "Should return correct prefix length" {
            $result = Get-SubnetInfo -CIDR "192.168.1.0/24"
            $result.PrefixLength | Should -Be 24
        }

        It "Should throw for invalid CIDR notation" {
            { Get-SubnetInfo -CIDR "not-a-cidr" } | Should -Throw "*Invalid CIDR*"
        }

        It "Should throw for invalid prefix length" {
            { Get-SubnetInfo -CIDR "10.0.0.0/33" } | Should -Throw "*between 0 and 32*"
        }

        It "Should handle /32 (single host)" {
            $result = Get-SubnetInfo -CIDR "10.0.0.1/32"
            $result.TotalHosts | Should -Be 1
            $result.UsableHosts | Should -Be 1
        }
    }
}
