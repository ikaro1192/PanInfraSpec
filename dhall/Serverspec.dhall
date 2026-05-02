-- dhall/Serverspec.dhall
-- Per-backend Dhall prelude for Serverspec.
-- Smart constructors enforce Resource × State pairing at the input boundary
-- (Defense-in-depth layer 1). See specification.md §3.2 / §5.4.

let CompareOp = < Lt | Le | Gt | Ge | Eq >

let AttrLeaf =
      < ALText   : Text
      | ALNat    : Natural
      | ALBool   : Bool
      | ALSymbol : Text
      >

let AttrValue =
      < AVText    : Text
      | AVNat     : Natural
      | AVBool    : Bool
      | AVSymbol  : Text
      | AVList    : List AttrLeaf
      | AVRecord  : List { mapKey : Text, mapValue : AttrLeaf }
      | AVCompare : { op : CompareOp, value : AttrLeaf }
      >

let Assertion =
      { kind       : Text
      , primaryKey : Text
      , attrs      : List { mapKey : Text, mapValue : AttrValue }
      }

-- Phase 1 resource states ---------------------------------------------------

let ServiceState = < Running | Enabled >
let PackageState = < Installed >
let PortState    = < Listening | WithProtocol : Text >
let CommandState = < ExitCode : Natural >

-- Phase 2 expanded states ---------------------------------------------------

let PermissionScope = < Owner | Group | Others >

let FileState =
      < Exist
      | OwnedBy     : Text
      | GroupedInto : Text
      | Mode        : Natural
      | Contains    : Text
      -- Phase 2 follow-up: simple file-type matchers (no arguments)
      | BeFile
      | BeDirectory
      | BeSymlink
      | BeSocket
      | BePipe
      | BeBlockDevice
      | BeCharacterDevice
      | BeImmutable
      -- Phase 2 follow-up: permission chain matchers
      | Readable
      | ReadableByScope   : PermissionScope
      | ReadableByUser    : Text
      | Writable
      | WritableByScope   : PermissionScope
      | WritableByUser    : Text
      | Executable
      | ExecutableByScope : PermissionScope
      | ExecutableByUser  : Text
      -- Phase 2 follow-up: contain chain matchers
      | ContainsFromTo : { pattern : Text, from : Text, to : Text }
      | ContainsAfter  : { pattern : Text, after : Text }
      | ContainsBefore : { pattern : Text, before : Text }
      -- Phase 2 follow-up: link / mounted matchers
      | LinkedTo        : Text
      | Mounted
      | MountedWith     : List { mapKey : Text, mapValue : Text }
      | MountedOnlyWith : List { mapKey : Text, mapValue : Text }
      >

let UserState =
      < Exist
      | HasUid           : Natural
      | BelongsToGroup   : Text
      | HasHomeDirectory : Text
      | HasLoginShell    : Text
      -- Phase 2 follow-up
      | BelongsToPrimaryGroup : Text
      | HasAuthorizedKey      : Text
      >

let GroupState  = < Exist | HasGid : Natural >
let ProcessState =
      < Running
      | RunByUser : Text
      -- Phase 2 follow-up: its(:group/:args/:count)
      | HasGroup : Text
      | HasArgs  : Text
      | HasCount : Natural
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
      -- Phase 2 follow-up
      | Up
      | HasIpv6Address : Text
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
      | ReachableWith : { port : Natural, proto : Text, timeout : Natural }
      >
let Ip6tablesState = < HasRule : Text >
let IpfilterState  = < HasRule : Text >
let IpnatState     = < HasRule : Text >
let IptablesState  = < HasRule : Text >
let RoutingTableState =
      < HasEntry     : { destination : Text, gateway : Text }
      | HasEntryFull : { destination : Text, gateway : Text, interface : Text }
      >

-- PR-2 Linux system / kernel resources --------------------------------------

let SelinuxState = < Enforcing | Permissive | Disabled >
let SelinuxModuleState = < Enabled | Installed | WithVersion : Text >
let LinuxAuditSystemState = < Running | Enabled >
let LinuxKernelParameterState = < HasValue : Text >
let CgroupState =
      < HasParameter : { name : Text, value : Text } >

-- Issue #3 follow-up: compound matchers --------------------------------------

let WindowsFeatureState = < Installed | InstalledBy : Text >
let CronState =
      < HasEntry       : Text
      | HasEntryAsUser : { entry : Text, user : Text }
      >
let X509CertificateState =
      < ValidityInDaysCompare : { op : CompareOp, value : Natural } >
let WindowsRegistryKeyState =
      < HasProperty      : { name : Text, propertyType : Text }
      | HasPropertyValue : { name : Text, propertyType : Text, value : Natural }
      >

-- Attribute encoders --------------------------------------------------------

-- Convert PermissionScope to the Ruby symbol payload Serverspec expects on
-- @be_readable.by(:owned)@ etc. (`:owned`/`:grouped`/`:others`, not the more
-- intuitive `:owner` family).
let scopeName =
      \(sc : PermissionScope) ->
        merge
          { Owner  = "owned"
          , Group  = "grouped"
          , Others = "others"
          }
          sc

-- Lift a List of (Text -> Text) record entries into a List of (Text ->
-- AttrLeaf) entries by wrapping each value in @AttrLeaf.ALText@. Used when a
-- Dhall constructor takes a Text-only record (e.g. @MountedWith@) but the IR
-- requires AttrLeaf payloads.
let textRecToAttrLeafRec =
      \(rec : List { mapKey : Text, mapValue : Text }) ->
        List/fold
          { mapKey : Text, mapValue : Text }
          rec
          (List { mapKey : Text, mapValue : AttrLeaf })
          ( \(e : { mapKey : Text, mapValue : Text }) ->
            \(acc : List { mapKey : Text, mapValue : AttrLeaf }) ->
                [ { mapKey = e.mapKey
                  , mapValue = AttrLeaf.ALText e.mapValue
                  }
                ]
              # acc
          )
          ([] : List { mapKey : Text, mapValue : AttrLeaf })

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
      \(s : PortState) ->
        merge
          { Listening    = toMap { listening = AttrValue.AVBool True }
          , WithProtocol =
              \(p : Text) ->
                toMap
                  { listening = AttrValue.AVBool True
                  , protocol  = AttrValue.AVText p
                  }
          }
          s

let fileStateAttrs =
      \(s : FileState) ->
        merge
          { Exist       = toMap { exist = AttrValue.AVBool True }
          , OwnedBy     = \(u : Text) -> toMap { owned_by = AttrValue.AVText u }
          , GroupedInto = \(g : Text) -> toMap { grouped_into = AttrValue.AVText g }
          , Mode        = \(m : Natural) -> toMap { mode = AttrValue.AVNat m }
          , Contains    = \(p : Text) -> toMap { contains = AttrValue.AVText p }
          -- Phase 2 follow-up: simple file-type matchers
          , BeFile            = toMap { file_type        = AttrValue.AVBool True }
          , BeDirectory       = toMap { directory        = AttrValue.AVBool True }
          , BeSymlink         = toMap { symlink          = AttrValue.AVBool True }
          , BeSocket          = toMap { socket           = AttrValue.AVBool True }
          , BePipe            = toMap { pipe             = AttrValue.AVBool True }
          , BeBlockDevice     = toMap { block_device     = AttrValue.AVBool True }
          , BeCharacterDevice = toMap { character_device = AttrValue.AVBool True }
          , BeImmutable       = toMap { immutable        = AttrValue.AVBool True }
          -- Phase 2 follow-up: permission chain matchers. The base flag
          -- (e.g. `readable`) is always emitted alongside any modifier; the
          -- emit layer collapses both keys into a single chained Ruby line.
          , Readable        = toMap { readable = AttrValue.AVBool True }
          , ReadableByScope =
              \(sc : PermissionScope) ->
                toMap
                  { readable          = AttrValue.AVBool True
                  , readable_by_scope = AttrValue.AVSymbol (scopeName sc)
                  }
          , ReadableByUser =
              \(u : Text) ->
                toMap
                  { readable         = AttrValue.AVBool True
                  , readable_by_user = AttrValue.AVText u
                  }
          , Writable        = toMap { writable = AttrValue.AVBool True }
          , WritableByScope =
              \(sc : PermissionScope) ->
                toMap
                  { writable          = AttrValue.AVBool True
                  , writable_by_scope = AttrValue.AVSymbol (scopeName sc)
                  }
          , WritableByUser =
              \(u : Text) ->
                toMap
                  { writable         = AttrValue.AVBool True
                  , writable_by_user = AttrValue.AVText u
                  }
          , Executable        = toMap { executable = AttrValue.AVBool True }
          , ExecutableByScope =
              \(sc : PermissionScope) ->
                toMap
                  { executable          = AttrValue.AVBool True
                  , executable_by_scope = AttrValue.AVSymbol (scopeName sc)
                  }
          , ExecutableByUser =
              \(u : Text) ->
                toMap
                  { executable         = AttrValue.AVBool True
                  , executable_by_user = AttrValue.AVText u
                  }
          -- Phase 2 follow-up: contain chain matchers
          , ContainsFromTo =
              \(c : { pattern : Text, from : Text, to : Text }) ->
                toMap
                  { contains      = AttrValue.AVText c.pattern
                  , contains_from = AttrValue.AVText c.from
                  , contains_to   = AttrValue.AVText c.to
                  }
          , ContainsAfter =
              \(c : { pattern : Text, after : Text }) ->
                toMap
                  { contains       = AttrValue.AVText c.pattern
                  , contains_after = AttrValue.AVText c.after
                  }
          , ContainsBefore =
              \(c : { pattern : Text, before : Text }) ->
                toMap
                  { contains        = AttrValue.AVText c.pattern
                  , contains_before = AttrValue.AVText c.before
                  }
          -- Phase 2 follow-up: link / mounted matchers
          , LinkedTo = \(p : Text) -> toMap { linked_to = AttrValue.AVText p }
          , Mounted  = toMap { be_mounted = AttrValue.AVBool True }
          , MountedWith =
              \(rec : List { mapKey : Text, mapValue : Text }) ->
                toMap
                  { be_mounted   = AttrValue.AVBool True
                  , mounted_with = AttrValue.AVRecord (textRecToAttrLeafRec rec)
                  }
          , MountedOnlyWith =
              \(rec : List { mapKey : Text, mapValue : Text }) ->
                toMap
                  { be_mounted        = AttrValue.AVBool True
                  , mounted_only_with =
                      AttrValue.AVRecord (textRecToAttrLeafRec rec)
                  }
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
          , BelongsToPrimaryGroup =
              \(g : Text) -> toMap { belongs_to_primary_group = AttrValue.AVText g }
          , HasAuthorizedKey =
              \(k : Text) -> toMap { authorized_key = AttrValue.AVText k }
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
          , HasGroup  = \(g : Text)    -> toMap { group = AttrValue.AVText g }
          , HasArgs   = \(a : Text)    -> toMap { args  = AttrValue.AVText a }
          , HasCount  = \(n : Natural) -> toMap { count = AttrValue.AVNat n }
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
          , Up             = toMap { up = AttrValue.AVBool True }
          , HasIpv6Address = \(a : Text) -> toMap { ipv6_address = AttrValue.AVText a }
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
          , ReachableWith =
              \(r : { port : Natural, proto : Text, timeout : Natural }) ->
                toMap
                  { reachable      = AttrValue.AVBool True
                  , reachable_with =
                      AttrValue.AVRecord
                        [ { mapKey = "port",    mapValue = AttrLeaf.ALNat  r.port }
                        , { mapKey = "proto",   mapValue = AttrLeaf.ALText r.proto }
                        , { mapKey = "timeout", mapValue = AttrLeaf.ALNat  r.timeout }
                        ]
                  }
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
          , HasEntryFull =
              \(e : { destination : Text, gateway : Text, interface : Text }) ->
                [ { mapKey = e.destination
                  , mapValue =
                      AttrValue.AVRecord
                        [ { mapKey = "destination", mapValue = AttrLeaf.ALText e.destination }
                        , { mapKey = "gateway",     mapValue = AttrLeaf.ALText e.gateway }
                        , { mapKey = "interface",   mapValue = AttrLeaf.ALText e.interface }
                        ]
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
          { Enabled     = toMap { enabled   = AttrValue.AVBool True }
          , Installed   = toMap { installed = AttrValue.AVBool True }
          , WithVersion =
              \(v : Text) ->
                toMap
                  { installed = AttrValue.AVBool True
                  , version   = AttrValue.AVText v
                  }
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

let windowsFeatureStateAttrs =
      \(s : WindowsFeatureState) ->
        merge
          { Installed   = toMap { installed = AttrValue.AVBool True }
          , InstalledBy =
              \(m : Text) ->
                toMap
                  { installed      = AttrValue.AVBool True
                  , install_method = AttrValue.AVText m
                  }
          }
          s

let cronStateAttrs =
      \(s : CronState) ->
        merge
          { HasEntry = \(e : Text) -> toMap { entry = AttrValue.AVText e }
          , HasEntryAsUser =
              \(p : { entry : Text, user : Text }) ->
                toMap
                  { entry      = AttrValue.AVText p.entry
                  , entry_user = AttrValue.AVText p.user
                  }
          }
          s

let x509CertificateStateAttrs =
      \(s : X509CertificateState) ->
        merge
          { ValidityInDaysCompare =
              \(c : { op : CompareOp, value : Natural }) ->
                toMap
                  { validity_in_days =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALNat c.value }
                  }
          }
          s

let windowsRegistryKeyStateAttrs =
      \(s : WindowsRegistryKeyState) ->
        merge
          { HasProperty =
              \(p : { name : Text, propertyType : Text }) ->
                toMap
                  { property_args =
                      AttrValue.AVList
                        [ AttrLeaf.ALText   p.name
                        , AttrLeaf.ALSymbol p.propertyType
                        ]
                  }
          , HasPropertyValue =
              \(p : { name : Text, propertyType : Text, value : Natural }) ->
                toMap
                  { property_value_args =
                      AttrValue.AVList
                        [ AttrLeaf.ALText   p.name
                        , AttrLeaf.ALSymbol p.propertyType
                        , AttrLeaf.ALNat    p.value
                        ]
                  }
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

let windowsFeature
    : Text -> WindowsFeatureState -> Assertion
    = \(name : Text) ->
      \(s : WindowsFeatureState) ->
        { kind = "windows_feature"
        , primaryKey = name
        , attrs = windowsFeatureStateAttrs s
        }

-- cron is a singleton: there is only one cron table per host.
let cron
    : CronState -> Assertion
    = \(s : CronState) ->
        { kind = "cron"
        , primaryKey = "cron"
        , attrs = cronStateAttrs s
        }

let x509Certificate
    : Text -> X509CertificateState -> Assertion
    = \(path : Text) ->
      \(s : X509CertificateState) ->
        { kind = "x509_certificate"
        , primaryKey = path
        , attrs = x509CertificateStateAttrs s
        }

let windowsRegistryKey
    : Text -> WindowsRegistryKeyState -> Assertion
    = \(path : Text) ->
      \(s : WindowsRegistryKeyState) ->
        { kind = "windows_registry_key"
        , primaryKey = path
        , attrs = windowsRegistryKeyStateAttrs s
        }

in  { AttrValue         = AttrValue
    , AttrLeaf          = AttrLeaf
    , CompareOp         = CompareOp
    , Assertion         = Assertion
    , ServiceState      = ServiceState
    , PackageState      = PackageState
    , PortState         = PortState
    , FileState         = FileState
    , PermissionScope   = PermissionScope
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
    , WindowsFeatureState       = WindowsFeatureState
    , CronState                 = CronState
    , X509CertificateState      = X509CertificateState
    , WindowsRegistryKeyState   = WindowsRegistryKeyState
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
    , windowsFeature        = windowsFeature
    , cron                  = cron
    , x509Certificate       = x509Certificate
    , windowsRegistryKey    = windowsRegistryKey
    , targetBackend     = "serverspec"
    }
