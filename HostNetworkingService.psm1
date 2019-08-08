#########################################################################
# Global Initialize
$WorkingDir="$env:SystemRoot\System32"
function Get-VmComputeNativeMethods()
{
        $signature = @'
                     [DllImport("vmcompute.dll")]
                     public static extern void HNSCall([MarshalAs(UnmanagedType.LPWStr)] string method, [MarshalAs(UnmanagedType.LPWStr)] string path, [MarshalAs(UnmanagedType.LPWStr)] string request, [MarshalAs(UnmanagedType.LPWStr)] out string response);
'@

    # Compile into runtime type
    Add-Type -MemberDefinition $signature -Namespace VmCompute.HNS.PrivatePInvoke -Name NativeMethods -PassThru
}

#########################################################################
# Networks
#########################################################################

function Get-HnsNetwork
{
    param
    (
        [parameter(Mandatory=$false)] [string] $Id = [Guid]::Empty,
        [parameter(Mandatory=$false)] [switch] $Detailed = $false
    )

    if ($Id -ne [Guid]::Empty)
    {
        $action = $null
        if ($Detailed.IsPresent) {
            $action = "detailed"
        }

        return Invoke-HNSRequest -Method GET -Type networks -Id $id -Action $action
    }
    else
    {
        return Invoke-HNSRequest -Method GET -Type networks
    }
}

function Remove-HnsNetwork
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
        [Object[]] $InputObjects
    )
    begin {$Objects = @()}
    process {$Objects += $InputObjects; }
    end {
        $Objects | foreach {  Invoke-HNSRequest -Method DELETE -Type  networks -Id $_.Id }
    }
}



#########################################################################

# Get-HNSEndpoints
<#
    .Synopsis
    Get All HNS Endpoint Objects

    .Description

    .Parameter Type

#>
function Get-HnsEndpoint
{
    param
    (
        [parameter(Mandatory=$false)] [string] $Id = [Guid]::Empty
    )

    if ($Id -ne [Guid]::Empty)
    {
        return Invoke-HNSRequest -Method GET -Type endpoints -Id $id
    }
    else
    {
        return Invoke-HNSRequest -Method GET -Type endpoints
    }
}

function Remove-HnsEndpoint
{
    param
    (
        [parameter(Mandatory = $true, ValueFromPipeline = $True, ValueFromPipelinebyPropertyName = $True)]
        [Object[]] $InputObjects
    )

    begin {$objects = @()}
    process {$Objects += $InputObjects; }
    end {
        $Objects | foreach {  Invoke-HnsRequest -Method DELETE -Type endpoints -Id $_.Id  }
    }
}

function Get-HnsPolicyList {
    param
    (
        [parameter(Mandatory = $false)] [string] $Id = [Guid]::Empty
    )

    if ($Id -ne [Guid]::Empty)
    {
        return Invoke-HNSRequest -Method GET -Type policylists -Id $id
    }
    else
    {
        return Invoke-HNSRequest -Method GET -Type policylists
    }
}

function Remove-HnsPolicyList
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
        [Object[]] $InputObjects
    )
    begin {$Objects = @()}
    process {$Objects += $InputObjects; }
    end {
        $Objects | foreach { Invoke-HnsRequest -Method DELETE -Type  policylists -Id $_.Id }
    }
}

function Get-HnsNamespace
{
    param
    (
        [parameter(Mandatory=$false)] [string] $Id = [Guid]::Empty
    )

    if ($Id -ne [Guid]::Empty)
    {
        return Invoke-HNSRequest -Method GET -Type namespaces -Id $id
    }
    else
    {
        return Invoke-HNSRequest -Method GET -Type namespaces
    }
}

function Remove-HnsNamespace
{
    param
    (
        [parameter(Mandatory = $true, ValueFromPipeline = $True, ValueFromPipelinebyPropertyName = $True)]
        [Object[]] $InputObjects
    )

    begin {$objects = @()}
    process {$Objects += $InputObjects; }
    end {
        $Objects | foreach {  Invoke-HnsRequest -Method DELETE -Type namespaces -Id $_.Id  }
    }
}

function Invoke-HnsRequest
{
    param
    (
        [ValidateSet('GET', 'POST', 'DELETE')]
        [parameter(Mandatory=$true)] [string] $Method,
        [ValidateSet('networks', 'endpoints', 'policylists', 'namespaces')]
        [parameter(Mandatory=$true)] [string] $Type,
        [parameter(Mandatory=$false)] [string] $Action = $null,
        [parameter(Mandatory=$false)] [string] $Data = $null,
        [parameter(Mandatory=$false)] [Guid] $Id = [Guid]::Empty
    )

    $hnsPath = "/$Type"

    if ($id -ne [Guid]::Empty)
    {
        $hnsPath += "/$id";
    }

    if ($Action)
    {
        $hnsPath += "/$Action";
    }

    $request = "";
    if ($Data)
    {
        $request = $Data
    }

    $output = "";
    $response = "";
    Write-Verbose "Invoke-HNSRequest Method[$Method] Path[$hnsPath] Data[$request]"

    $hnsApi = Get-VmComputeNativeMethods
    $hnsApi::HNSCall($Method, $hnsPath, "$request", [ref] $response);

    Write-Verbose "Result : $response"
    if ($response)
    {
        try {
            $output = ($response | ConvertFrom-Json);
        } catch {
            Write-Error $_.Exception.Message
            return ""
        }
        if ($output.Error)
        {
             Write-Error $output;
        }
        $output = $output.Output;
    }

    return $output;
}

#########################################################################
Export-ModuleMember -Function Get-HnsNetwork
Export-ModuleMember -Function Remove-HnsNetwork
Export-ModuleMember -Function Get-HnsEndpoint
Export-ModuleMember -Function Remove-HnsEndpoint
Export-ModuleMember -Function Get-HnsPolicyList
Export-ModuleMember -Function Remove-HnsPolicyList
Export-ModuleMember -Function Get-HnsNamespace
Export-ModuleMember -Function Remove-HnsNamespace
