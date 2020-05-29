#########################################################################
# Global Initialize
function Get-VmComputeNativeMethods()
{
        $signature = @'
                     [DllImport("vmcompute.dll")]
                     public static extern void HNSCall([MarshalAs(UnmanagedType.LPWStr)] string method, [MarshalAs(UnmanagedType.LPWStr)] string path, [MarshalAs(UnmanagedType.LPWStr)] string request, [MarshalAs(UnmanagedType.LPWStr)] out string response);
'@

    # Compile into runtime type
    Add-Type -MemberDefinition $signature -Namespace VmCompute.HNSPrivate.PrivatePInvoke -Name NativeMethods -PassThru
}

Add-Type -TypeDefinition @"
    public enum ModifyRequestType
    {
        Add,
        Remove,
        Update,
        Refresh
    };

    public enum EndpointResourceType
    {
        Port,
        Policy,
    };
    public enum NetworkResourceType
    {
        DNS,
        Extension,
        Policy,
        Subnet,
        IPSubnet
    };
    public enum NamespaceResourceType
    {
    Container,
    Endpoint,
    };
"@

#########################################################################
# Configuration
#########################################################################
function Get-HnsSwitchExtensions
{
    param
    (
        [parameter(Mandatory=$true)] [string] $NetworkId
    )

    return (Get-HnsNetwork $NetworkId).Extensions
}

function Set-HnsSwitchExtension
{
    param
    (
        [parameter(Mandatory=$true)] [string] $NetworkId,
        [parameter(Mandatory=$true)] [string] $ExtensionId,
        [parameter(Mandatory=$true)] [bool]   $state
    )

    # { "Extensions": [ { "Id": "...", "IsEnabled": true|false } ] }
    $req = @{
        "Extensions"=@(@{
            "Id"=$ExtensionId;
            "IsEnabled"=$state;
        };)
    }
    Invoke-HnsRequest -Method POST -Type networks -Id $NetworkId -Data (ConvertTo-Json $req)
}

#########################################################################
# Activities
#########################################################################
function Get-HnsActivity
{
    [cmdletbinding()]Param()
    return Invoke-HnsRequest -Type activities -Method GET
}
#########################################################################
# Namespaces
#########################################################################
function New-HnsNamespace {
    param
    (
        [parameter(Mandatory = $false)] [Guid[]] $Endpoints = $null,
        [parameter(Mandatory = $false)] [switch] $Default
    )
    $namespace=@{IsDefault=[bool]$Default;}
    $namespace=Invoke-HnsRequest -Type namespaces -Method POST  -Data (ConvertTo-Json  $namespace -Depth 10)
    foreach ($id in $Endpoints) {
        $endpoint = @{
            Type = "Endpoint";
            Data = @{
                Id = $id
            }
        };

        Invoke-HnsRequest -Type namespaces -Method POST -Action "addResource" -Id $namespace.ID -Data (ConvertTo-Json  $endpoint -Depth 10) | Out-Null
    }
    return $namespace
}

function Update-HnsNamespace {
    param
    (
        [parameter(Mandatory = $true)] [Guid] $NamespaceID= $null,
        [parameter(Mandatory = $false)] [Guid[]] $EndpointsToAdd = $null,
        [parameter(Mandatory = $false)] [Guid[]] $EndpointsToRemove = $null
    )

    foreach ($id in $EndpointsToAdd) {
        $endpoint = @{
            Type = "Endpoint";
            Data = @{
                Id = $id
            }
        };

        Invoke-HnsRequest -Type namespaces -Method POST -Action "addResource" -Id $NamespaceID -Data (ConvertTo-Json  $endpoint -Depth 10) | Out-Null
    }

    foreach ($id in $EndpointsToRemove) {
        $endpoint = @{
            Type = "Endpoint";
            Data = @{
                Id = $id
            }
        };

        Invoke-HnsRequest -Type namespaces -Method POST -Action "removeResource" -Id $NamespaceID -Data (ConvertTo-Json  $endpoint -Depth 10) | Out-Null
    }
}

#########################################################################
# Globals
#########################################################################
function Get-HnsGlobal {
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory=$false)] [string] $Id = $null
    )

    return Invoke-HnsRequest -Type globals -Method GET -Id $Id
}

function Get-HnsGlobalVersion {
    return Get-HnsGlobal -Id "version"
}

function Get-HnsPortPools {
    return Invoke-HnsRequest -Type portpools -Method GET
}

function New-HnsRoute {
    param
    (
        [parameter(Mandatory = $false)] [Guid[]] $Endpoints = $null,
        [parameter(Mandatory = $true)] [string] $DestinationPrefix,
        [parameter(Mandatory = $false)] [switch] $EncapEnabled,
        [parameter(Mandatory = $false)] [string] $NextHop,
        [parameter(Mandatory = $false)] [switch] $MonitorDynamicEndpoints
    )

    $route = @{
            Type = "ROUTE";
            DestinationPrefix = $DestinationPrefix;
            NeedEncap = $EncapEnabled.IsPresent;
    };

    if($NextHop)
    {
        $route.NextHop = $NextHop
    }

    if ($MonitorDynamicEndpoints.IsPresent)
    {
        $route += @{
            AutomaticEndpointMonitor = $MonitorDynamicEndpoints.IsPresent;
        }
    }


    $policyLists = @{
        References = @(
            get-endpointReferences $Endpoints;
        );

        Policies   = @(
            $route
        );
    }

    Invoke-HnsRequest -Method POST -Type policylists -Data (ConvertTo-Json  $policyLists -Depth 10)
}


function New-HnsProxyPolicy {
    param
    (
        [parameter(Mandatory = $false)] [Guid[]] $Endpoints = $null,
        [parameter(Mandatory = $false)] [string] $DestinationPrefix,
        [parameter(Mandatory = $false)] [string] $DestinationPort,
        [parameter(Mandatory = $false)] [string] $Destination,
        [parameter(Mandatory = $false)] [string[]] $ExceptionList,
        [parameter(Mandatory = $false)] [bool] $OutboundNat
    )

    $ProxyPolicy   = @{
        Type = "PROXY";
    };

    if ($DestinationPrefix) {
        $ProxyPolicy['IP'] = $DestinationPrefix
    }
    if ($DestinationPort) {
        $ProxyPolicy['Port'] = $DestinationPort
    }
    if ($ExceptionList) {
        $ProxyPolicy['ExceptionList'] = $ExceptionList
    }
    if ($Destination) {
        $ProxyPolicy['Destination'] = $Destination
    }
    if ($OutboundNat) {
        $ProxyPolicy['OutboundNat'] = $OutboundNat
    }
    foreach ($id in $Endpoints) {
        $ep = Get-HnsEndpoint -Id $id
        $ep.Policies += $ProxyPolicy

        $epu   = @{
            ID = $id;
            Policies=$ep.Policies;
        };
        Invoke-HnsRequest -Method POST -Type endpoints -Id $id -Data (ConvertTo-Json  $epu -Depth 10)
    }
}

function Remove-HnsProxyPolicy {
    param
    (
        [parameter(Mandatory = $false)] [Guid[]] $Endpoints = $null
    )

    foreach ($id in $Endpoints) {
        $ep = Get-HnsEndpoint -Id $id
        $Policies = $ep.Policies | ? { $_.Type -ne "PROXY" }

        $epu   = @{
            ID = $id;
            Policies=$Policies;
        };

        Invoke-HnsRequest -Method POST -Type endpoints -Id $id -Data (ConvertTo-Json  $epu -Depth 10)
    }


}

function New-HnsLoadBalancer {
    param
    (
        [parameter(Mandatory = $false)] [Guid[]] $Endpoints = $null,
        [parameter(Mandatory = $true)] [int] $InternalPort,
        [parameter(Mandatory = $true)] [int] $ExternalPort,
        [parameter(Mandatory = $true)] [int] $Protocol,
        [parameter(Mandatory = $false)] [string] $Vip,
        [parameter(Mandatory = $false)] [string] $SourceVip,
        [parameter(Mandatory = $false)] [switch] $LocalRoutedVip,
        [parameter(Mandatory = $false)] [switch] $ILB,
        [parameter(Mandatory = $false)] [switch] $DSR,
        [parameter(Mandatory = $false)] [switch] $PreserveDip,
        [parameter(Mandatory = $false)] [switch] $UseMux
    )

    $elb = @{}
    $elb.Type = "ELB"
    $elb.InternalPort = $InternalPort
    $elb.ExternalPort = $ExternalPort
    $elb.Protocol = $Protocol

    if(-not [String]::IsNullOrEmpty($vip))
    {
        $elb.VIPs = @()
        $elb.VIPS += $Vip
    }

    if(-not [String]::IsNullOrEmpty($SourceVip))
    {

        $elb.SourceVIP += $SourceVip
    }

    if($ILB.IsPresent)
    {
        $elb.ILB = $true
    }

    if ($LocalRoutedVip.IsPresent)
    {
        $elb.LocalRoutedVip = $true
    }

    if($DSR.IsPresent)
    {
        $elb.IsDSR = $true
        if ($UseMux.IsPresent)
        {
            $elb.UseMux = $true
            if($PreserveDip.IsPresent)
            {
                $elb.PreserveDip = $true
            }
        }
    }

    $policyLists = @{
        References = @(
            get-endpointReferences $Endpoints;
        );

        Policies   = @(
            $elb
        );
    }

    Invoke-HnsRequest -Method POST -Type policylists -Data ( ConvertTo-Json  $policyLists -Depth 10)
}

function get-endpointReferences {
    param
    (
        [parameter(Mandatory = $true)] [Guid[]] $Endpoints = $null
    )
    if ($Endpoints ) {
        $endpointReference = @()
        foreach ($endpoint in $Endpoints)
        {
            $endpointReference += "/endpoints/$endpoint"
        }
        return $endpointReference
    }
    return @()
}

#########################################################################
# Networks
#########################################################################

Add-Type -TypeDefinition @"
    [System.Flags]
    public enum NetworkFlags
    {
        None = 0,
        EnableDns = 1,
        EnableDhcp = 2,
        EnableMirroring = 4,
    }

    [System.Flags]
    public enum EndpointFlags
    {
        None = 0,
        RemoteEndpoint = 1,
        DisableICC = 2,
        EnableMirroring = 4,
        EnableDhcp = 32
    }
"@


function New-HnsIcsNetwork
{
    param
    (
        [parameter(Mandatory = $false)] [string] $Name,
        [parameter(Mandatory = $false)] [string] $AddressPrefix,
        [parameter(Mandatory = $false)] [string] $Gateway,
        [parameter(Mandatory= $false)] [NetworkFlags] $NetworkFlags = 0,
        [parameter(Mandatory= $false)] [int] $Vlan = 0,
        [parameter(Mandatory = $false)] [string] $DNSServer,
        [parameter(Mandatory = $false)] [int]    $ICSFlags = 0,
        [parameter(Mandatory = $false)] [string] $InterfaceConstraint = $null
    )
    $NetworkSpecificParams = @{
    }

    if ($InterfaceConstraint)
    {
        $NetworkSpecificParams += @{
            ExternalInterfaceConstraint = $InterfaceConstraint;
        }
    }

    $spolicy = @{}


    $NetworkSpecificParams += @{
        Flags = $NetworkFlags;
        IsolateSwitch = $true; # Workaround until we fix the DHCP issue
    }

    return new-hnsnetwork -type ics `
        -Name $Name -AddressPrefix $AddressPrefix -Gateway $Gateway `
        -DNSServer $DNSServer `
        -AdditionalParams @{"ICSFlags" = $ICSFlags } `
        -NetworkSpecificParams $NetworkSpecificParams `
        -vlan $Vlan
}

function New-HnsNetwork
{
    param
    (
        [parameter(Mandatory=$false, Position=0)]
        [string] $JsonString,
        [ValidateSet('ICS', 'Internal', 'Transparent', 'NAT', 'Overlay', 'L2Bridge', 'L2Tunnel', 'Layered', 'Private')]
        [parameter(Mandatory = $false, Position = 0)]
        [string] $Type,
        [parameter(Mandatory = $false)] [string] $Name,
        [parameter(Mandatory = $false)] $AddressPrefix,
        [parameter(Mandatory = $false)] $Gateway,
        [HashTable[]][parameter(Mandatory=$false)] $Policies, #  @(@{"Type"="ACL"; "Action"="Block"; "Direction"="Out"; "Priority"=500})
        [parameter(Mandatory= $false)] [int] $Vlan = 0,
        [parameter(Mandatory= $false)] [int] $Vsid = 0,
        [parameter(Mandatory = $false)] [switch] $IPv6,
        [parameter(Mandatory = $false)] [string] $DNSServer,
        [parameter(Mandatory = $false)] [string] $AdapterName,
        [HashTable][parameter(Mandatory=$false)] $AdditionalParams, #  @ {"ICSFlags" = 0; }
        [HashTable][parameter(Mandatory=$false)] $NetworkSpecificParams, #  @ {"InterfaceConstraint" = ""; }
        [parameter(Mandatory = $false)] [int] $VxlanPort = 0
    )

    Begin {
        if (!$JsonString) {
            $netobj = @{
                Type          = $Type;
            };

            if ($Name) {
                $netobj += @{
                    Name = $Name;
                }
            }

            if ($Policies) {
                $netobj.Policies += $Policies
            }

            # Coalesce prefix/gateway into subnet objects.
            if ($AddressPrefix) {
                $subnets += @()
                $prefixes = @($AddressPrefix)
                $gateways = @($Gateway)

                $len = $prefixes.length
                for ($i = 0; $i -lt $len; $i++) {
                    $subnet = @{ 
                        AddressPrefix = $prefixes[$i];
                        Policies = @();
                    }
                    if ($i -lt $gateways.length -and $gateways[$i]) {
                        $subnet += @{ 
                            GatewayAddress = $gateways[$i]; 
                        }
                        if ($vlan -gt 0) {
                                $subnet.Policies += @{"Type"= "VLAN"; "VLAN" = $VLAN;}
                        }
                        if ($Vsid -gt 0) {
                            $subnet.Policies += @{"Type"= "VSID"; "VSID" = $VSID;}
                        }
                    }
                    $subnets += $subnet  
                }
            

                

                $netobj += @{ Subnets = $subnets }
            }

            if ($IPv6.IsPresent) {
                $netobj += @{ IPv6 = $true }
            }

            if ($AdapterName) {
                $netobj += @{ NetworkAdapterName = $AdapterName; }
            }

            if ($AdditionalParams) {
                $netobj += @{
                    AdditionalParams = @{}
                }

                foreach ($param in $AdditionalParams.Keys) {
                    $netobj.AdditionalParams += @{
                        $param = $AdditionalParams[$param];
                    }
                }
            }

            if ($NetworkSpecificParams) {
                $netobj += $NetworkSpecificParams
            }

            if ($VxlanPort -gt 0) {
                $netobj += @{ "VxlanPort" = $VxlanPort }
            }

            $JsonString = ConvertTo-Json $netobj -Depth 10
        }
    }
    Process{
        return Invoke-HnsRequest -Method POST -Type networks -Data $JsonString
    }
}

function Refresh-HnsNetwork
{
    param
    (
        [parameter(Mandatory=$true)] [string] $Id
    )
    return Invoke-HnsNetworkRequest -Method POST -Action refresh -Id $id -Data " "
}

function MessageGuest-HnsNetwork
{
    param
    (
        [parameter(Mandatory=$true)] [string] $Id,
        [parameter(Mandatory=$true)] [string] $JsonString
    )
    return Invoke-HnsNetworkRequest -Method POST -Action messageGuest -Id $id -Data $JsonString
}

#########################################################################
# Endpoints
#########################################################################

function Get-HnsEndpointStats
{
    param
    (
        [parameter(Mandatory=$false)] [string] $Id = [Guid]::Empty
    )
    return Invoke-HnsRequest -Method GET -Type endpointstats -Id $id
}

function New-HnsEndpoint
{
    param
    (
        [parameter(Mandatory=$false, Position = 0)] [string] $JsonString = $null,
        [parameter(Mandatory = $false, Position = 0)] [Guid] $NetworkId,
        [parameter(Mandatory = $false)] [string] $Name,
        [parameter(Mandatory= $false)] [EndpointFlags] $Flags = 0,
        [parameter(Mandatory = $false)] [string] $IPAddress,
        [parameter(Mandatory = $false)] [uint16] $PrefixLength,
        [parameter(Mandatory = $false)] [string] $IPv6Address,
        [parameter(Mandatory = $false)] [uint16] $IPv6PrefixLength,
        [parameter(Mandatory = $false)] [string] $GatewayAddress,
        [parameter(Mandatory = $false)] [string] $GatewayAddressV6,
        [parameter(Mandatory = $false)] [string] $DNSServerList,
        [parameter(Mandatory = $false)] [string] $MacAddress,
        [parameter(Mandatory = $false)] [switch] $RemoteEndpoint,
        [parameter(Mandatory = $false)] [switch] $EnableOutboundNat,
        [HashTable][parameter(Mandatory=$false)] $OutboundNatPolicy, #  @ {"LocalRoutedVip" = true; "VIP" = ""; ExceptionList = ["", ""]}
        [parameter(Mandatory = $false)] [string[]] $OutboundNatExceptions,
        [parameter(Mandatory = $false)] [string[]] $RoutePrefixes, # Deprecate this. use RoutePolicies
        [HashTable[]][parameter(Mandatory=$false)] $RoutePolicies, #  @( @ {"DestinationPrefix" = ""; "NeedEncap" = true; "NextHop" = ""} )
        [HashTable][parameter(Mandatory=$false)] $InboundNatPolicy, #  @ {"InternalPort" = "80"; "ExternalPort" = "8080"}
        [HashTable][parameter(Mandatory=$false)] $PAPolicy #  @ {"PA" = "1.2.3.4"; }
    )

    begin
    {
        if ($JsonString)
        {
            $EndpointData = $JsonString | ConvertTo-Json | ConvertFrom-Json
        }
        else
        {
            $endpoint = @{
                VirtualNetwork = $NetworkId;
                Policies       = @();
                Flags          = $Flags;
            }

            if ($Name) {
                $endpoint += @{
                    Name = $Name;
                }
            }

            if ($MacAddress) {
                $endpoint += @{
                    MacAddress     = $MacAddress;
                }
            }

            if ($IPAddress) {
                $endpoint += @{
                    IPAddress      = $IPAddress;
                }
            }
            if ($PrefixLength) {
                $endpoint += @{
                    PrefixLength   = $PrefixLength;
                }
            }
            if ($GatewayAddress) {
                $endpoint += @{
                    GatewayAddress = $GatewayAddress;
                }
            }

            if ($IPv6Address) {
                $endpoint += @{
                    IPv6Address = $IPv6Address;
                }
            }
            if ($IPv6PrefixLength) {
                $endpoint += @{
                    IPv6PrefixLength = $IPv6PrefixLength;
                }
            }
            if ($GatewayAddressV6) {
                $endpoint += @{
                    GatewayAddressV6 = $GatewayAddressV6;
                }
            }

            if ($DNSServerList) {
                $endpoint += @{
                    DNSServerList      = $DNSServerList;
                }
            }
            if ($RemoteEndpoint.IsPresent) {
                $endpoint += @{
                    IsRemoteEndpoint      = $true;
                }
            }

            if ($EnableOutboundNat.IsPresent) {

                $outboundPolicy = @{}
                $outboundPolicy.Type = "OutBoundNAT"

                if ($OutboundNatExceptions) {
                    $outboundPolicy.ExceptionList = @()
                    foreach ($exp in $OutboundNatExceptions)
                    {
                        $outboundPolicy.ExceptionList += $exp
                    }
                }

                $endpoint.Policies +=  $outboundPolicy;
            }

            if ($OutboundNatPolicy)
            {
                $opolicy = @{
                    Type = "OutBoundNAT";
                }
                $opolicy += $OutboundNatPolicy;
                $endpoint.Policies +=  $opolicy;
            }

            if ($RoutePolicies)
            {
                foreach ($routepolicy in $RoutePolicies)
                {
                    $rPolicy = @{
                        Type = "ROUTE";
                        DestinationPrefix = $routepolicy["DestinationPrefix"];
                        NeedEncap = $true;
                    }
                    if ($routepolicy.ContainsKey("NextHop"))
                    {
                        $rPolicy.NextHop = $routepolicy["NextHop"]
                    }

                    $endpoint.Policies += $rPolicy
                }
            }

            # Deprecate this
            if ($RoutePrefixes)
            {
                foreach ($routeprefix in $RoutePrefixes) {
                    $endpoint.Policies += @{
                            Type = "ROUTE";
                            DestinationPrefix = $routeprefix;
                            NeedEncap = $true;
                    }
                }
            }

            if ($InboundNatPolicy) {
                $InboundNatPolicy += @{
                    Type = "NAT";
                }
                $endpoint.Policies += $InboundNatPolicy
            }

            if ($PAPolicy) {
                $endpoint.Policies += @{
                        Type = "PA";
                        PA = $PAPolicy["PA"];
                }
            }

            # Try to Generate the data
            $EndpointData = convertto-json $endpoint -Depth 10
        }
    }

    Process
    {
        return Invoke-HnsRequest -Method POST -Type endpoints -Data $EndpointData
    }
}


function New-HnsRemoteEndpoint
{
    param
    (
        [parameter(Mandatory = $true)] [Guid] $NetworkId,
        [parameter(Mandatory = $false)] [string] $IPAddress,
        [parameter(Mandatory = $false)] [string] $MacAddress,
        [parameter(Mandatory = $false)] [string] $DNSServerList
    )

    return New-HnsEndpoint -NetworkId $NetworkId -IPAddress $IPAddress -MacAddress $MacAddress -DNSServerList $DNSServerList -RemoteEndpoint
}


function Attach-HnsHostEndpoint
{
    param
    (
     [parameter(Mandatory=$true)] [Guid] $EndpointID,
     [parameter(Mandatory=$true)] [int] $CompartmentID
     )
    $request = @{
        SystemType    = "Host";
        CompartmentId = $CompartmentID;
    };

    return Invoke-HnsEndpointRequest -Method POST -Data (ConvertTo-Json $request -Depth 10) -Action attach -Id $EndpointID
}

function Attach-HnsVMEndpoint
{
    param
    (
     [parameter(Mandatory=$true)] [Guid] $EndpointID,
     [parameter(Mandatory=$true)] [string] $VMNetworkAdapterName
     )

    $request = @{
        VirtualNicName   = $VMNetworkAdapterName;
        SystemType    = "VirtualMachine";
    };
    return Invoke-HnsEndpointRequest -Method POST -Data (ConvertTo-Json $request -Depth 10) -Action attach -Id $EndpointID

}

function Attach-HnsEndpoint
{
    param
    (
        [parameter(Mandatory=$true)] [Guid] $EndpointID,
        [parameter(Mandatory=$true)] [int] $CompartmentID,
        [parameter(Mandatory=$true)] [string] $ContainerID
    )
     $request = @{
        ContainerId = $ContainerID;
        SystemType="Container";
        CompartmentId = $CompartmentID;
    };

    return Invoke-HnsEndpointRequest -Method POST -Data (ConvertTo-Json $request -Depth 10) -Action attach -Id $EndpointID
}

function Detach-HnsVMEndpoint
{
    param
    (
        [parameter(Mandatory=$true)] [Guid] $EndpointID
    )
    $request = @{
        SystemType  = "VirtualMachine";
    };

    return Invoke-HnsEndpointRequest -Method POST -Data (ConvertTo-Json $request -Depth 10) -Action detach -Id $EndpointID
}

function Detach-HnsHostEndpoint
{
    param
    (
        [parameter(Mandatory=$true)] [Guid] $EndpointID
    )
    $request = @{
        SystemType  = "Host";
    };

    return Invoke-HnsEndpointRequest -Method POST -Data (ConvertTo-Json $request -Depth 10) -Action detach -Id $EndpointID
}

function Detach-HnsEndpoint
{
    param
    (
        [parameter(Mandatory=$true)] [Guid] $EndpointID,
        [parameter(Mandatory=$true)] [string] $ContainerID
    )

    $request = @{
        ContainerId = $ContainerID;
        SystemType="Container";
    };

    return Invoke-HnsEndpointRequest -Method POST -Data (ConvertTo-Json $request -Depth 10) -Action detach -Id $EndpointID
}

function Modify-HnsEndpoint
{
    param
    (
        [parameter(Mandatory=$true)] [Guid] $Id,
        [parameter(Mandatory=$true)] [ModifyRequestType] $RequestType,
        [parameter(Mandatory=$false)] [EndpointResourceType] $ResourceType,
        [HashTable][parameter(Mandatory=$false)] $Settings,
        [HashTable[]][parameter(Mandatory=$false)] $PolicyArray
    )

    $msettings = @{
        RequestType = "$RequestType";
        ResourceType = "$ResourceType";
    }

    if ($Settings)
    {
        $msettings += @{
            Settings = $Settings;
        }
    }
    elseif($PolicyArray)
    {
        $policies = @{
            Policies = $PolicyArray;
        }
        $msettings += @{
            Settings = $policies;
        }
    }

    return Invoke-HnsEndpointRequest -Method POST -Data (ConvertTo-Json $msettings -Depth 10) -Action modify -Id $Id
}
#########################################################################

function Invoke-HnsEndpointRequest
{
    param
    (
        [ValidateSet('GET', 'POST', 'DELETE')]
        [parameter(Mandatory=$true)] [string] $Method,
        [ValidateSet('attach', 'detach', 'detailed', 'modify', 'refresh')]
        [parameter(Mandatory=$false)] [string] $Action = $null,
        [parameter(Mandatory=$false)] [string] $Data = $null,
        [parameter(Mandatory=$false)] [string] $Id = $null
    )
    return Invoke-HnsRequest -Method $Method -Type endpoints -Action $Action -Data $Data -Id $Id
}

function Invoke-HnsNetworkRequest
{
    param
    (
        [ValidateSet('GET', 'POST', 'DELETE')]
        [parameter(Mandatory=$true)] [string] $Method,
        [ValidateSet('refresh', 'detailed', 'messageGuest')]
        [parameter(Mandatory=$false)] [string] $Action = $null,
        [parameter(Mandatory=$false)] [string] $Data = $null,
        [parameter(Mandatory=$false)] [string] $Id = $null
    )
    return Invoke-HnsRequest -Method $Method -Type networks -Action $Action -Data $Data -Id $Id
}

#########################################################################

function Invoke-HnsRequest
{
    param
    (
        [ValidateSet('GET', 'POST', 'DELETE')]
        [parameter(Mandatory=$true)] [string] $Method,
        [ValidateSet('networks', 'endpoints', 'activities', 'policylists', 'endpointstats', 'plugins', 'namespaces', 'globals', 'portpools')]
        [parameter(Mandatory=$true)] [string] $Type,
        [parameter(Mandatory=$false)] [string] $Action = $null,
        [parameter(Mandatory=$false)] [string] $Data = $null,
        [parameter(Mandatory=$false)] [string] $Id = $null
    )

    $hnsPath = "/$Type"

    if ($id)
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
    Write-Verbose "Invoke-HnsRequest Type[$Type] Method[$Method] Path[$hnsPath] Data[$request]"

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

Export-ModuleMember -Function Get-HnsActivity
Export-ModuleMember -Function Get-HnsSwitchExtensions
Export-ModuleMember -Function Set-HnsSwitchExtension

Export-ModuleMember -Function Get-HnsEndpointStats
Export-ModuleMember -Function Get-HnsGlobalVersion

Export-ModuleMember -Function Get-HnsPortPools

Export-ModuleMember -Function New-HnsNetwork
Export-ModuleMember -Function New-HnsIcsNetwork
Export-ModuleMember -Function Refresh-HnsNetwork

Export-ModuleMember -Function New-HnsEndpoint
Export-ModuleMember -Function New-HnsRemoteEndpoint
Export-ModuleMember -Function New-HnsProxyPolicy

Export-ModuleMember -Function Remove-HnsProxyPolicy

Export-ModuleMember -Function Attach-HnsHostEndpoint
Export-ModuleMember -Function Attach-HnsVMEndpoint
Export-ModuleMember -Function Attach-HnsEndpoint
Export-ModuleMember -Function Detach-HnsHostEndpoint
Export-ModuleMember -Function Detach-HnsVMEndpoint
Export-ModuleMember -Function Detach-HnsEndpoint
Export-ModuleMember -Function Modify-HnsEndpoint


Export-ModuleMember -Function New-HnsNamespace
Export-ModuleMember -Function Update-HnsNamespace
Export-ModuleMember -Function New-HnsRoute
Export-ModuleMember -Function New-HnsLoadBalancer

Export-ModuleMember -Function Invoke-HnsNetworkRequest
Export-ModuleMember -Function Invoke-HnsEndpointRequest
Export-ModuleMember -Function Invoke-HnsRequest
