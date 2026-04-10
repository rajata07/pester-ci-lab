function Test-PortConnectivity {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [int]$Port,

        [int]$TimeoutMilliseconds = 3000
    )

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "Port must be between 1 and 65535"
    }

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectTask = $tcpClient.ConnectAsync($ComputerName, $Port)
        $connected = $connectTask.Wait($TimeoutMilliseconds)

        $result = [PSCustomObject]@{
            ComputerName = $ComputerName
            Port         = $Port
            IsOpen       = $connected
            ResponseTime = if ($connected) { "< ${TimeoutMilliseconds}ms" } else { "Timeout" }
        }
    }
    catch {
        $result = [PSCustomObject]@{
            ComputerName = $ComputerName
            Port         = $Port
            IsOpen       = $false
            ResponseTime = "Error: $($_.Exception.Message)"
        }
    }
    finally {
        if ($tcpClient) { $tcpClient.Dispose() }
    }

    return $result
}

function Get-DnsResolution {
    param(
        [Parameter(Mandatory)]
        [string]$Hostname,

        [ValidateSet("A", "AAAA", "CNAME", "MX", "All")]
        [string]$RecordType = "A"
    )

    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        throw "Hostname cannot be empty"
    }

    $dnsResult = Resolve-DnsName -Name $Hostname -Type $RecordType -ErrorAction Stop

    $records = foreach ($record in $dnsResult) {
        [PSCustomObject]@{
            Name       = $record.Name
            Type       = $record.QueryType
            TTL        = $record.TTL
            IPAddress  = if ($record.IPAddress) { $record.IPAddress } else { $record.NameHost }
        }
    }

    return [PSCustomObject]@{
        Hostname   = $Hostname
        RecordType = $RecordType
        Records    = $records
        Count      = ($records | Measure-Object).Count
    }
}

function Get-SubnetInfo {
    param(
        [Parameter(Mandatory)]
        [string]$CIDR
    )

    if ($CIDR -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$') {
        throw "Invalid CIDR notation. Expected format: x.x.x.x/y"
    }

    $parts = $CIDR -split '/'
    $ip = [System.Net.IPAddress]::Parse($parts[0])
    $prefixLength = [int]$parts[1]

    if ($prefixLength -lt 0 -or $prefixLength -gt 32) {
        throw "Prefix length must be between 0 and 32"
    }

    $maskBytes = [byte[]]::new(4)
    for ($i = 0; $i -lt 4; $i++) {
        $bitsInOctet = [Math]::Min(8, [Math]::Max(0, $prefixLength - ($i * 8)))
        $maskBytes[$i] = [byte](256 - [Math]::Pow(2, 8 - $bitsInOctet))
    }
    $subnetMask = [System.Net.IPAddress]::new($maskBytes)

    $ipBytes = $ip.GetAddressBytes()
    $networkBytes = [byte[]]::new(4)
    for ($i = 0; $i -lt 4; $i++) {
        $networkBytes[$i] = $ipBytes[$i] -band $maskBytes[$i]
    }
    $networkAddress = [System.Net.IPAddress]::new($networkBytes)

    $totalHosts = [Math]::Pow(2, 32 - $prefixLength)
    $usableHosts = if ($prefixLength -lt 31) { $totalHosts - 2 } else { $totalHosts }

    return [PSCustomObject]@{
        CIDR           = $CIDR
        NetworkAddress = $networkAddress.ToString()
        SubnetMask     = $subnetMask.ToString()
        PrefixLength   = $prefixLength
        TotalHosts     = $totalHosts
        UsableHosts    = $usableHosts
    }
}

Export-ModuleMember -Function Test-PortConnectivity, Get-DnsResolution, Get-SubnetInfo
