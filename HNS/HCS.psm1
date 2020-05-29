
#########################################################################
# Global Initialize
function Get-HcsComputeNativeMethods()
{
        $signature = @'
                     [DllImport("vmcompute.dll")]
                     public static extern void HcsOpenComputeSystem([MarshalAs(UnmanagedType.LPWStr)] string Id, [MarshalAs(UnmanagedType.SysInt)] out IntPtr ComputeSystem,  [MarshalAs(UnmanagedType.LPWStr)] out string Result);
                     [DllImport("vmcompute.dll")]
                     public static extern void HcsCloseComputeSystem([MarshalAs(UnmanagedType.SysInt)] IntPtr ComputeSystem);
                     [DllImport("vmcompute.dll")]
                     public static extern void HcsModifyComputeSystem([MarshalAs(UnmanagedType.SysInt)] IntPtr ComputeSystem, [MarshalAs(UnmanagedType.LPWStr)] string Configuration, [MarshalAs(UnmanagedType.LPWStr)] out string Result);

'@

    # Compile into runtime type
    Add-Type -MemberDefinition $signature -Namespace HcsCompute.PrivatePInvoke -Name NativeMethods -PassThru
}

#########################################################################
# Containers
#########################################################################
{
    param
    (
        [ValidateSet('Process', 'HyperV')]
        [parameter(Mandatory=$false)] [string] $Isolation = "Process",
        [parameter(Mandatory=$false)] [string] $Configuration = $null,
        [parameter(Mandatory=$false)] [Guid] $EndpointId = [Guid]::Empty
    )

    $ComputeSystem = Create-HCSContainer -Isolation $Isolation -Configuration $Configuration

    $result = Start-HCSContainer -Isolation $Isolation -Configuration $Configuration

    return $ComputeSystem
}

function Create-HCSContainer
{
    param
    (
        [ValidateSet('Process', 'HyperV')]
        [parameter(Mandatory=$true)] [string] $Isolation,
        [parameter(Mandatory=$false)] [string] $Configuration = $null
    )

    $id = "";

    if (!$Configuration)
    {
        # Try to Generate the data
        $Configuration = Create-HCSComputeSystemObject -Isolation $Isolation -Id $id
    }


    $identity = 0;
    $result = "";
    $ComputeSystem = "";
    $HCSApi = Get-HcsComputeNativeMethods
    # $HCSApi::HcsCreateComputeSystem($Id.ToString(), $Configuration, [ref]$identity, [ref]$ComputeSystem, [ref]$result);

    Write-Verbose "Result : $result"

    return $ComputeSystem
}


function  Create-HCSComputeSystemObject
{
    param
    (
        [parameter(Mandatory=$true)] [string] $Id,
        [ValidateSet('Process', 'HyperV')]
        [parameter(Mandatory=$true)] [string] $Isolation
    )

    '''
    From : https://github.com/Microsoft/hcsshim/blob/master/interface.go

    // ContainerConfig is used as both the input of CreateContainer

    // and to convert the parameters to JSON for passing onto the HCS

    type ContainerConfig struct {

        SystemType                 string      // HCS requires this to be hard-coded to "Container"
        Name                       string      // Name of the container. We use the docker ID.
        Owner                      string      // The management platform that created this container
        IsDummy                    bool        // Used for development purposes.
        VolumePath                 string      `json:",omitempty"` // Windows volume path for scratch space. Used by Windows Server Containers only. Format \\?\\Volume{GUID}
        IgnoreFlushesDuringBoot    bool        // Optimization hint for container startup in Windows
        LayerFolderPath            string      `json:",omitempty"` // Where the layer folders are located. Used by Windows Server Containers only. Format  %root%\windowsfilter\containerID
        Layers                     []Layer     // List of storage layers. Required for Windows Server and Hyper-V Containers. Format ID=GUID;Path=%root%\windowsfilter\layerID
        Credentials                string      `json:",omitempty"` // Credentials information
        ProcessorCount             uint32      `json:",omitempty"` // Number of processors to assign to the container.
        ProcessorWeight            uint64      `json:",omitempty"` // CPU Shares 0..10000 on Windows; where 0 will be omitted and HCS will default.
        ProcessorMaximum           int64       `json:",omitempty"` // CPU maximum usage percent 1..100
        StorageIOPSMaximum         uint64      `json:",omitempty"` // Maximum Storage IOPS
        StorageBandwidthMaximum    uint64      `json:",omitempty"` // Maximum Storage Bandwidth in bytes per second
        StorageSandboxSize         uint64      `json:",omitempty"` // Size in bytes that the container system drive should be expanded to if smaller
        MemoryMaximumInMB          int64       `json:",omitempty"` // Maximum memory available to the container in Megabytes
        HostName                   string      // Hostname
        MappedDirectories          []MappedDir // List of mapped directories (volumes/mounts)
        HvPartition                bool        // True if it a Hyper-V Container
        EndpointList               []string    // List of networking endpoints to be attached to container
        NetworkSharedContainerName string      `json:",omitempty"` // Name (ID) of the container that we will share the network stack with.
        HvRuntime                  *HvRuntime  `json:",omitempty"` // Hyper-V container settings. Used by Hyper-V containers only. Format ImagePath=%root%\BaseLayerID\UtilityVM
        AllowUnqualifiedDNSQuery   bool        // True to allow unqualified DNS name resolution
        DNSSearchList              string      `json:",omitempty"` // Comma seperated list of DNS suffixes to use for name resolution
    }

    Sample Input : "CreateContainer id=fd0948ae8877a0308d8e992c9dd9184b7d691c2873d90e1d177fed969b253777 config={
        \"SystemType\":\"Container\",\"Name\":\"fd0948ae8877a0308d8e992c9dd9184b7d691c2873d90e1d177fed969b253777\",\"Owner\":\"docker\",
        \"IsDummy\":false,\"VolumePath\":\"\\\\\\\\?\\\\Volume{12feac5f-c66e-4565-8d5d-1efce798248f}\",
        \"IgnoreFlushesDuringBoot\":true,\"LayerFolderPath\":\"C:\\\\ProgramData\\\\docker\\\\windowsfilter\\\\fd0948ae8877a0308d8e992c9dd9184b7d691c2873d90e1d177fed969b253777\",
        \"Layers\":[{\"ID\":\"85a82a94-bc58-51f6-b36f-70b089bca922\",\"Path\":\"C:\\\\ProgramData\\\\docker\\\\windowsfilter\\\\32edab1efa68baa09704a37907101757b37d2bbd227fabb3be122aec0e014896\"}],
        \"HostName\":\"fd0948ae8877\",\"MappedDirectories\":[],\"HvPartition\":false,\"EndpointList\":[\"4dc85955-2b78-4186-afae-e1b72142192a\"],
        \"AllowUnqualifiedDNSQuery\":true}"
    '''
    #$id = "fd0948ae8877a0308d8e992c9dd9184b7d691c2873d90e1d177fed969b253777"
    $Configuration =
    @{
        SystemType="Container";
        Name = $id;
        Owner = "HCSTest";
        IsDummy = $false;
        VolumePath = "\\?\\Volume{12feac5f-c66e-4565-8d5d-1efce798248f}";
        IgnoreFlushesDuringBoot = $true;
        LayerFolderPath = 'C:\ProgramData\docker\windowsfilter\$id';
        Layers = $(
            @{
                ID = "";
                Path = "";
            };
        );
        HostName = "";
        MappedDirectories = $();
        HvPartition = $false;
        EndpointList = $("");
        AllowUnqualifiedDNSQuery = $false;

    };

    return $Configuration | ConvertTo-Json;
}

function Open-HCSContainer
{
    param
    (
        [parameter(Mandatory=$true)] [string] $ComputeSystemId
    )
    $computeSystem = 0
    $result = ""
    $HCSApi = Get-HcsComputeNativeMethods
    $HCSApi::HcsOpenComputeSystem($ComputeSystemId,[ref]$computeSystem, [ref]$result);
    Write-Verbose "Computesystem [$ComputeSystemId]=>[$computeSystem]"
    Write-Verbose "Result : $result"
    return $computeSystem
}

function Close-HCSContainer
{
    param
    (
        [parameter(Mandatory=$true)] [System.IntPtr] $ComputeSystem
    )
    $HCSApi = Get-HcsComputeNativeMethods
    $HCSApi::HcsCloseComputeSystem($ComputeSystem);
}

function Modify-HCSContainer
{
    param
    (
        [parameter(Mandatory=$true)] [string] $ComputeSystemId,
        [parameter(Mandatory=$true)] [string] $Configuration
    )
    $HCSApi = Get-HcsComputeNativeMethods
    $ComputeSystem = Open-HCSContainer -ComputeSystemId $ComputeSystemId
    $result = ""
    try {
        Write-Verbose "ModifyComputeSystem[$ComputeSystemId] : $Configuration"
        $HCSApi::HcsModifyComputeSystem($ComputeSystem, $Configuration, [ref]$result);
        Write-Verbose "Result : $result"
    } finally {
        Close-HCSContainer -ComputeSystem $ComputeSystem
    }

    return $result
}

function HotAdd-NetworkEndpoint-HCSContainer
{
    param
    (
        [parameter(Mandatory=$true)] [string] $Id = $null,
        [parameter(Mandatory=$true)] [guid] $EndpointId
    )

    $ResourceModificationRequestResponse = @{
        ResourceType = "Network";
        RequestType  = "Add";
        Settings     = $EndpointId.ToString();
    }
    Modify-HCSContainer -ComputeSystemId $Id `
                        -Configuration (ConvertTo-Json $ResourceModificationRequestResponse -Depth 10) `
                        -Verbose
}

function HotRemove-NetworkEndpoint-HCSContainer
{
    param
    (
        [parameter(Mandatory=$true)] [string] $Id = $null,
        [parameter(Mandatory=$true)] [guid] $EndpointId
    )

    $ResourceModificationRequestResponse = @{
        ResourceType = "Network";
        RequestType  = "Remove";
        Settings     = $EndpointId.ToString();
    }
    Modify-HCSContainer -ComputeSystemId $Id `
                        -Configuration (ConvertTo-Json $ResourceModificationRequestResponse -Depth 10) `
                        -Verbose
}

function HotAdd-NetworkEndpoint-HCSContainerV2
{
    param
    (
        [parameter(Mandatory=$true)] [string] $Id = $null,
        [parameter(Mandatory=$true)] [guid] $EndpointId
    )

    # PreAdd
    & {
        $networkRequest = [HCS.Schema.Requests.Guest.NetworkModifySettingRequest]::new()
        $networkRequest.AdapterId = $EndpointId
        $networkRequest.RequestType = "PreAdd"
        $networkRequest.Settings = Get-HnsEndpoint -Id $EndpointId

        $guestRequest = [HCS.Schema.Requests.System.ModifySettingRequest]::new()
        $guestRequest.ResourceType = "Network"
        $guestRequest.RequestType = "Add"
        $guestRequest.Settings = $networkRequest

        $request = [HCS.Schema.Requests.System.ModifySettingRequest]::new()
        $request.GuestRequest = $guestRequest
        Modify-HCSContainer -ComputeSystemId $Id `
                            -Configuration (ConvertTo-Json $request -Depth 10) `
                            -Verbose
    }

    # Add
    & {
        $networkRequest = [HCS.Schema.Requests.Guest.NetworkModifySettingRequest]::new()
        $networkRequest.AdapterId = $EndpointId
        $networkRequest.RequestType = "Add"

        $guestRequest = [HCS.Schema.Requests.System.ModifySettingRequest]::new()
        $guestRequest.ResourceType = "Network"
        $guestRequest.RequestType = "Add"
        $guestRequest.Settings = $networkRequest

        $request = [HCS.Schema.Requests.System.ModifySettingRequest]@{
            ResourcePath = "VirtualMachine/Devices/NetworkAdapters/$EndpointId";
            RequestType  = "Add";
            Settings     = @{
                EndpointId = $EndpointId;
            };
            GuestRequest = $guestRequest;
        }
        Modify-HCSContainer -ComputeSystemId $Id `
                            -Configuration (ConvertTo-Json $request -Depth 10) `
                            -Verbose
    }
}

function HotRemove-NetworkEndpoint-HCSContainerV2
{
    param
    (
        [parameter(Mandatory=$true)] [string] $Id = $null,
        [parameter(Mandatory=$true)] [guid] $EndpointId
    )

    $ResourceModificationRequestResponse = @{
        ResourcePath = "VirtualMachine/Devices/NetworkAdapters/$EndpointId";
        RequestType  = "Remove";
        Settings     = @{
            EndpointID = $EndpointId;
        };
    }

    Modify-HCSContainer -ComputeSystemId $Id `
                        -Configuration (ConvertTo-Json $ResourceModificationRequestResponse -Depth 10) `
                        -Verbose
}
#########################################################################

Export-ModuleMember -Function HotAdd-NetworkEndpoint-HCSContainer
Export-ModuleMember -Function HotRemove-NetworkEndpoint-HCSContainer
