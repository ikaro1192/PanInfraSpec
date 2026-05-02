-- dhall/Serverspec.dhall
-- Per-backend Dhall prelude for Serverspec.
-- Smart constructors enforce Resource × State pairing at the input boundary
-- (Defense-in-depth layer 1). See specification.md §3.2 / §5.4.

let AttrValue = < AVText : Text | AVNat : Natural | AVBool : Bool >

let Assertion =
      { kind       : Text
      , primaryKey : Text
      , attrs      : List { mapKey : Text, mapValue : AttrValue }
      }

-- Phase 1 resource states ---------------------------------------------------

let ServiceState = < Running | Enabled >
let PackageState = < Installed >
let PortState    = < Listening >
let CommandState = < ExitCode : Natural >

-- Phase 2 expanded states ---------------------------------------------------

let FileState =
      < Exist
      | OwnedBy     : Text
      | GroupedInto : Text
      | Mode        : Natural
      | Contains    : Text
      >

let UserState =
      < Exist
      | HasUid           : Natural
      | BelongsToGroup   : Text
      | HasHomeDirectory : Text
      | HasLoginShell    : Text
      >

let GroupState  = < Exist | HasGid : Natural >
let ProcessState =
      < Running
      | RunByUser : Text
      >
let MountState =
      < Mounted
      | OnDevice : Text
      | OfFstype : Text
      >
let InterfaceState =
      < Exist
      | HasSpeed       : Natural
      | HasIpv4Address : Text
      >
let KernelModuleState = < Loaded >

-- PR-1 network resources -----------------------------------------------------

let BondState   = < Exist | HasInterface : Text >
let BridgeState = < Exist | HasInterface : Text >
let DefaultGatewayState =
      < HasIpaddress : Text
      | HasInterface : Text
      >
let HostState =
      < Resolvable
      | Reachable
      | HasIpaddress : Text
      >
let Ip6tablesState = < HasRule : Text >
let IpfilterState  = < HasRule : Text >
let IpnatState     = < HasRule : Text >
let IptablesState  = < HasRule : Text >
let RoutingTableState =
      < HasEntry : { destination : Text, gateway : Text } >

-- PR-2 Linux system / kernel resources --------------------------------------

let SelinuxState = < Enforcing | Permissive | Disabled >
let SelinuxModuleState = < Enabled | Installed >
let LinuxAuditSystemState = < Running | Enabled >
let LinuxKernelParameterState = < HasValue : Text >
let CgroupState =
      < HasParameter : { name : Text, value : Text } >

-- PR-3 container resources --------------------------------------------------

let DockerContainerState =
      < Exist
      | Running
      | HasVolume : Text
      >
let DockerImageState = < Exist >
let LxcState = < Exist | Running >



-- Attribute encoders --------------------------------------------------------

let serviceStateAttrs =
      \(s : ServiceState) ->
        merge
          { Running = toMap { running = AttrValue.AVBool True }
          , Enabled = toMap { enabled = AttrValue.AVBool True }
          }
          s

let packageStateAttrs =
      \(_ : PackageState) -> toMap { installed = AttrValue.AVBool True }

let portStateAttrs =
      \(_ : PortState) -> toMap { listening = AttrValue.AVBool True }

let fileStateAttrs =
      \(s : FileState) ->
        merge
          { Exist       = toMap { exist = AttrValue.AVBool True }
          , OwnedBy     = \(u : Text) -> toMap { owned_by = AttrValue.AVText u }
          , GroupedInto = \(g : Text) -> toMap { grouped_into = AttrValue.AVText g }
          , Mode        = \(m : Natural) -> toMap { mode = AttrValue.AVNat m }
          , Contains    = \(p : Text) -> toMap { contains = AttrValue.AVText p }
          }
          s

let commandStateAttrs =
      \(s : CommandState) ->
        merge
          { ExitCode =
              \(i : Natural) -> toMap { `exit-status` = AttrValue.AVNat i }
          }
          s

let userStateAttrs =
      \(s : UserState) ->
        merge
          { Exist            = toMap { exist = AttrValue.AVBool True }
          , HasUid           = \(n : Natural) -> toMap { uid = AttrValue.AVNat n }
          , BelongsToGroup   = \(g : Text) -> toMap { belongs_to_group = AttrValue.AVText g }
          , HasHomeDirectory = \(p : Text) -> toMap { home_directory = AttrValue.AVText p }
          , HasLoginShell    = \(p : Text) -> toMap { login_shell = AttrValue.AVText p }
          }
          s

let groupStateAttrs =
      \(s : GroupState) ->
        merge
          { Exist  = toMap { exist = AttrValue.AVBool True }
          , HasGid = \(n : Natural) -> toMap { gid = AttrValue.AVNat n }
          }
          s

let processStateAttrs =
      \(s : ProcessState) ->
        merge
          { Running   = toMap { running = AttrValue.AVBool True }
          , RunByUser = \(u : Text) -> toMap { user = AttrValue.AVText u }
          }
          s

let mountStateAttrs =
      \(s : MountState) ->
        merge
          { Mounted  = toMap { mounted = AttrValue.AVBool True }
          , OnDevice = \(d : Text) -> toMap { device = AttrValue.AVText d }
          , OfFstype = \(t : Text) -> toMap { fstype = AttrValue.AVText t }
          }
          s

let interfaceStateAttrs =
      \(s : InterfaceState) ->
        merge
          { Exist          = toMap { exist = AttrValue.AVBool True }
          , HasSpeed       = \(n : Natural) -> toMap { speed = AttrValue.AVNat n }
          , HasIpv4Address = \(a : Text) -> toMap { ipv4_address = AttrValue.AVText a }
          }
          s

let kernelModuleStateAttrs =
      \(_ : KernelModuleState) -> toMap { loaded = AttrValue.AVBool True }

let bondStateAttrs =
      \(s : BondState) ->
        merge
          { Exist        = toMap { exist = AttrValue.AVBool True }
          , HasInterface = \(i : Text) -> toMap { interface = AttrValue.AVText i }
          }
          s

let bridgeStateAttrs =
      \(s : BridgeState) ->
        merge
          { Exist        = toMap { exist = AttrValue.AVBool True }
          , HasInterface = \(i : Text) -> toMap { interface = AttrValue.AVText i }
          }
          s

let defaultGatewayStateAttrs =
      \(s : DefaultGatewayState) ->
        merge
          { HasIpaddress = \(a : Text) -> toMap { ipaddress = AttrValue.AVText a }
          , HasInterface = \(i : Text) -> toMap { interface = AttrValue.AVText i }
          }
          s

let hostStateAttrs =
      \(s : HostState) ->
        merge
          { Resolvable   = toMap { resolvable = AttrValue.AVBool True }
          , Reachable    = toMap { reachable  = AttrValue.AVBool True }
          , HasIpaddress = \(a : Text) -> toMap { ipaddress = AttrValue.AVText a }
          }
          s

let ip6tablesStateAttrs =
      \(s : Ip6tablesState) ->
        merge
          { HasRule = \(r : Text) -> toMap { rule = AttrValue.AVText r } }
          s

let ipfilterStateAttrs =
      \(s : IpfilterState) ->
        merge
          { HasRule = \(r : Text) -> toMap { rule = AttrValue.AVText r } }
          s

let ipnatStateAttrs =
      \(s : IpnatState) ->
        merge
          { HasRule = \(r : Text) -> toMap { rule = AttrValue.AVText r } }
          s

let iptablesStateAttrs =
      \(s : IptablesState) ->
        merge
          { HasRule = \(r : Text) -> toMap { rule = AttrValue.AVText r } }
          s

-- routing_table is a wildcard kind: each HasEntry produces one (destination,
-- gateway) attribute pair, where the destination becomes the dynamic mapKey.
-- toMap cannot be used here because the field name is value-dependent.
let routingTableStateAttrs =
      \(s : RoutingTableState) ->
        merge
          { HasEntry =
              \(e : { destination : Text, gateway : Text }) ->
                [ { mapKey = e.destination
                  , mapValue = AttrValue.AVText e.gateway
                  }
                ]
          }
          s

let selinuxStateAttrs =
      \(s : SelinuxState) ->
        merge
          { Enforcing  = toMap { enforcing  = AttrValue.AVBool True }
          , Permissive = toMap { permissive = AttrValue.AVBool True }
          , Disabled   = toMap { disabled   = AttrValue.AVBool True }
          }
          s

let selinuxModuleStateAttrs =
      \(s : SelinuxModuleState) ->
        merge
          { Enabled   = toMap { enabled   = AttrValue.AVBool True }
          , Installed = toMap { installed = AttrValue.AVBool True }
          }
          s

let linuxAuditSystemStateAttrs =
      \(s : LinuxAuditSystemState) ->
        merge
          { Running = toMap { running = AttrValue.AVBool True }
          , Enabled = toMap { enabled = AttrValue.AVBool True }
          }
          s

let linuxKernelParameterStateAttrs =
      \(s : LinuxKernelParameterState) ->
        merge
          { HasValue = \(v : Text) -> toMap { value = AttrValue.AVText v } }
          s

-- cgroup is a wildcard kind: HasParameter projects to a single attribute pair
-- whose mapKey is the parameter name (e.g. "cpu.shares"). toMap cannot be
-- used because the field name is value-dependent.
let cgroupStateAttrs =
      \(s : CgroupState) ->
        merge
          { HasParameter =
              \(p : { name : Text, value : Text }) ->
                [ { mapKey = p.name
                  , mapValue = AttrValue.AVText p.value
                  }
                ]
          }
          s

let dockerContainerStateAttrs =
      \(s : DockerContainerState) ->
        merge
          { Exist     = toMap { exist   = AttrValue.AVBool True }
          , Running   = toMap { running = AttrValue.AVBool True }
          , HasVolume = \(v : Text) -> toMap { volume = AttrValue.AVText v }
          }
          s

let dockerImageStateAttrs =
      \(_ : DockerImageState) -> toMap { exist = AttrValue.AVBool True }

let lxcStateAttrs =
      \(s : LxcState) ->
        merge
          { Exist   = toMap { exist   = AttrValue.AVBool True }
          , Running = toMap { running = AttrValue.AVBool True }
          }
          s

-- Smart constructors --------------------------------------------------------

let service
    : Text -> ServiceState -> Assertion
    = \(name : Text) ->
      \(s : ServiceState) ->
        { kind = "service", primaryKey = name, attrs = serviceStateAttrs s }

let package
    : Text -> PackageState -> Assertion
    = \(name : Text) ->
      \(s : PackageState) ->
        { kind = "package", primaryKey = name, attrs = packageStateAttrs s }

let port
    : Natural -> PortState -> Assertion
    = \(p : Natural) ->
      \(s : PortState) ->
        { kind = "port", primaryKey = Natural/show p, attrs = portStateAttrs s }

let file
    : Text -> FileState -> Assertion
    = \(path : Text) ->
      \(s : FileState) ->
        { kind = "file", primaryKey = path, attrs = fileStateAttrs s }

let command
    : Text -> CommandState -> Assertion
    = \(cmd : Text) ->
      \(s : CommandState) ->
        { kind = "command", primaryKey = cmd, attrs = commandStateAttrs s }

let user
    : Text -> UserState -> Assertion
    = \(name : Text) ->
      \(s : UserState) ->
        { kind = "user", primaryKey = name, attrs = userStateAttrs s }

let group
    : Text -> GroupState -> Assertion
    = \(name : Text) ->
      \(s : GroupState) ->
        { kind = "group", primaryKey = name, attrs = groupStateAttrs s }

let process
    : Text -> ProcessState -> Assertion
    = \(name : Text) ->
      \(s : ProcessState) ->
        { kind = "process", primaryKey = name, attrs = processStateAttrs s }

let mount
    : Text -> MountState -> Assertion
    = \(path : Text) ->
      \(s : MountState) ->
        { kind = "mount", primaryKey = path, attrs = mountStateAttrs s }

let interface
    : Text -> InterfaceState -> Assertion
    = \(name : Text) ->
      \(s : InterfaceState) ->
        { kind = "interface", primaryKey = name, attrs = interfaceStateAttrs s }

let kernelModule
    : Text -> KernelModuleState -> Assertion
    = \(name : Text) ->
      \(s : KernelModuleState) ->
        { kind = "kernel-module", primaryKey = name, attrs = kernelModuleStateAttrs s }

let bond
    : Text -> BondState -> Assertion
    = \(name : Text) ->
      \(s : BondState) ->
        { kind = "bond", primaryKey = name, attrs = bondStateAttrs s }

let bridge
    : Text -> BridgeState -> Assertion
    = \(name : Text) ->
      \(s : BridgeState) ->
        { kind = "bridge", primaryKey = name, attrs = bridgeStateAttrs s }

-- defaultGateway is a singleton: takes no Text argument; primaryKey is fixed
-- to the kind name to satisfy non-empty validation. The emitter omits the
-- (<primaryKey>) argument from the generated `describe` block.
let defaultGateway
    : DefaultGatewayState -> Assertion
    = \(s : DefaultGatewayState) ->
        { kind = "default_gateway"
        , primaryKey = "default_gateway"
        , attrs = defaultGatewayStateAttrs s
        }

let host
    : Text -> HostState -> Assertion
    = \(name : Text) ->
      \(s : HostState) ->
        { kind = "host", primaryKey = name, attrs = hostStateAttrs s }

let ip6tables
    : Text -> Ip6tablesState -> Assertion
    = \(table : Text) ->
      \(s : Ip6tablesState) ->
        { kind = "ip6tables", primaryKey = table, attrs = ip6tablesStateAttrs s }

let ipfilter
    : Text -> IpfilterState -> Assertion
    = \(label : Text) ->
      \(s : IpfilterState) ->
        { kind = "ipfilter", primaryKey = label, attrs = ipfilterStateAttrs s }

let ipnat
    : Text -> IpnatState -> Assertion
    = \(label : Text) ->
      \(s : IpnatState) ->
        { kind = "ipnat", primaryKey = label, attrs = ipnatStateAttrs s }

let iptables
    : Text -> IptablesState -> Assertion
    = \(table : Text) ->
      \(s : IptablesState) ->
        { kind = "iptables", primaryKey = table, attrs = iptablesStateAttrs s }

-- routingTable is a singleton (no primary key); each HasEntry attaches one
-- destination/gateway pair to the same describe block.
let routingTable
    : RoutingTableState -> Assertion
    = \(s : RoutingTableState) ->
        { kind = "routing_table"
        , primaryKey = "routing_table"
        , attrs = routingTableStateAttrs s
        }

-- selinux is a singleton; the three states are mutually exclusive in practice
-- but the validator does not enforce mutual exclusion (a misuse manifests as
-- a Ruby-level test failure).
let selinux
    : SelinuxState -> Assertion
    = \(s : SelinuxState) ->
        { kind = "selinux"
        , primaryKey = "selinux"
        , attrs = selinuxStateAttrs s
        }

let selinuxModule
    : Text -> SelinuxModuleState -> Assertion
    = \(name : Text) ->
      \(s : SelinuxModuleState) ->
        { kind = "selinux_module"
        , primaryKey = name
        , attrs = selinuxModuleStateAttrs s
        }

let linuxAuditSystem
    : LinuxAuditSystemState -> Assertion
    = \(s : LinuxAuditSystemState) ->
        { kind = "linux_audit_system"
        , primaryKey = "linux_audit_system"
        , attrs = linuxAuditSystemStateAttrs s
        }

let linuxKernelParameter
    : Text -> LinuxKernelParameterState -> Assertion
    = \(name : Text) ->
      \(s : LinuxKernelParameterState) ->
        { kind = "linux_kernel_parameter"
        , primaryKey = name
        , attrs = linuxKernelParameterStateAttrs s
        }

let cgroup
    : Text -> CgroupState -> Assertion
    = \(name : Text) ->
      \(s : CgroupState) ->
        { kind = "cgroup", primaryKey = name, attrs = cgroupStateAttrs s }

let dockerContainer
    : Text -> DockerContainerState -> Assertion
    = \(name : Text) ->
      \(s : DockerContainerState) ->
        { kind = "docker_container"
        , primaryKey = name
        , attrs = dockerContainerStateAttrs s
        }

let dockerImage
    : Text -> DockerImageState -> Assertion
    = \(name : Text) ->
      \(s : DockerImageState) ->
        { kind = "docker_image"
        , primaryKey = name
        , attrs = dockerImageStateAttrs s
        }

let lxc
    : Text -> LxcState -> Assertion
    = \(name : Text) ->
      \(s : LxcState) ->
        { kind = "lxc", primaryKey = name, attrs = lxcStateAttrs s }

in  { AttrValue         = AttrValue
    , Assertion         = Assertion
    , ServiceState      = ServiceState
    , PackageState      = PackageState
    , PortState         = PortState
    , FileState         = FileState
    , CommandState      = CommandState
    , UserState         = UserState
    , GroupState        = GroupState
    , ProcessState      = ProcessState
    , MountState        = MountState
    , InterfaceState    = InterfaceState
    , KernelModuleState = KernelModuleState
    , BondState           = BondState
    , BridgeState         = BridgeState
    , DefaultGatewayState = DefaultGatewayState
    , HostState           = HostState
    , Ip6tablesState      = Ip6tablesState
    , IpfilterState       = IpfilterState
    , IpnatState          = IpnatState
    , IptablesState       = IptablesState
    , RoutingTableState   = RoutingTableState
    , SelinuxState              = SelinuxState
    , SelinuxModuleState        = SelinuxModuleState
    , LinuxAuditSystemState     = LinuxAuditSystemState
    , LinuxKernelParameterState = LinuxKernelParameterState
    , CgroupState               = CgroupState
    , DockerContainerState      = DockerContainerState
    , DockerImageState          = DockerImageState
    , LxcState                  = LxcState
    , service           = service
    , package           = package
    , port              = port
    , file              = file
    , command           = command
    , user              = user
    , group             = group
    , process           = process
    , mount             = mount
    , interface         = interface
    , kernelModule      = kernelModule
    , bond              = bond
    , bridge            = bridge
    , defaultGateway    = defaultGateway
    , host              = host
    , ip6tables         = ip6tables
    , ipfilter          = ipfilter
    , ipnat             = ipnat
    , iptables          = iptables
    , routingTable      = routingTable
    , selinux               = selinux
    , selinuxModule         = selinuxModule
    , linuxAuditSystem      = linuxAuditSystem
    , linuxKernelParameter  = linuxKernelParameter
    , cgroup                = cgroup
    , dockerContainer       = dockerContainer
    , dockerImage           = dockerImage
    , lxc                   = lxc
    , targetBackend     = "serverspec"
    }
