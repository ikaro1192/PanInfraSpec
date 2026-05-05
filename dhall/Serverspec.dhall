-- dhall/Serverspec.dhall
-- Per-backend Dhall prelude for Serverspec.
-- Smart constructors enforce Resource × State pairing at the input boundary
-- (Defense-in-depth layer 1).

let CompareOp = < Lt | Le | Gt | Ge | Eq | Match >

-- Typed expression sub-IR (issue #57). Promotes the most common
-- `ALRubyExpr` patterns into typed, backend-agnostic constructors so plans
-- can express them in Dhall without dropping into an opaque string.
-- Kept flat (non-recursive) because Dhall lacks recursive types — grow
-- additively as new recurring escape-hatch patterns are observed.
--
-- The binary `Add`/`Sub`/`Mul`/`Div` constructors take `Operand` (a
-- numeric literal or a host customAttribute reference) on both sides,
-- never another `Expr`, for the same Dhall-no-recursive-types reason
-- that keeps `Selector` boolean composition Haskell-only. Compose more
-- than two terms with `FactIntScaled` (for the `fact * m1 * ... / d`
-- shape) or fall back to `ALRubyExpr` for anything richer.
let Operand =
      < Lit  : Natural
      | Fact : Text
      >

let Expr =
      < FactInt       : Text
      | FactIntScaled : { name : Text, muls : List Natural, divisor : Natural }
      | Add           : { left : Operand, right : Operand }
      | Sub           : { left : Operand, right : Operand }
      | Mul           : { left : Operand, right : Operand }
      | Div           : { left : Operand, right : Operand }
      >

let AttrLeaf =
      < ALText     : Text
      | ALNat      : Natural
      | ALBool     : Bool
      | ALSymbol   : Text
      | ALRegex    : Text
      | ALRubyExpr : Text
      | ALExpr     : Expr
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
      , module     : Optional Text
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
      < ValidityInDaysCompare          : { op : CompareOp, value : Natural }
      | ValidityInDaysCompareExpr      : { op : CompareOp, value : Text }
      | ValidityInDaysCompareTypedExpr : { op : CompareOp, value : Expr }
      >
let WindowsRegistryKeyState =
      < HasProperty      : { name : Text, propertyType : Text }
      | HasPropertyValue : { name : Text, propertyType : Text, value : Natural }
      >

-- Phase 3 (serverspec.org coverage completion): 12 remaining kinds -----------

let LxcState  = < Exist | Running >

let MailAliasState = < AliasedTo : Text >

let PpaState     = < Exist | Enabled >
let YumrepoState = < Exist | Enabled >

let IisAppPoolState =
      < Exist
      | HasDotnetVersion : Text
      >

let IisWebsiteState =
      < Exist
      | Enabled
      | Running
      | InAppPool       : Text
      | HasPhysicalPath : Text
      >

let MysqlConfigState =
      < EqText           : Text
      | EqNat            : Natural
      | Compare          : { op : CompareOp, value : Natural }
      | CompareExpr      : { op : CompareOp, value : Text }
      | CompareTypedExpr : { op : CompareOp, value : Expr }
      >

let PhpConfigState =
      < EqText           : Text
      | EqNat            : Natural
      | Compare          : { op : CompareOp, value : Natural }
      | CompareExpr      : { op : CompareOp, value : Text }
      | CompareTypedExpr : { op : CompareOp, value : Expr }
      | Match            : Text
      >

let X509PrivateKeyState =
      < Encrypted
      | NotEncrypted
      | Valid
      | HasMatchingCertificate : Text
      >

let ZfsState =
      < Exist
      | HasProperty : List { mapKey : Text, mapValue : Text }
      >

let DockerContainerState =
      < Exist
      | Running
      | HasVolume       : { containerPath : Text, hostPath : Text }
      | InspectEqText   : { keyPath : Text, value : Text }
      | InspectEqNat    : { keyPath : Text, value : Natural }
      | InspectEqBool   : { keyPath : Text, value : Bool }
      | InspectEqSymbol : { keyPath : Text, value : Text }
      | InspectInclude  : { keyPath : Text, value : Text }
      | InspectionNotInclude : { key : Text, value : Text }
      >

let DockerImageState =
      < Exist
      | InspectEqText   : { keyPath : Text, value : Text }
      | InspectEqNat    : { keyPath : Text, value : Natural }
      | InspectEqBool   : { keyPath : Text, value : Bool }
      | InspectEqSymbol : { keyPath : Text, value : Text }
      | InspectInclude  : { keyPath : Text, value : Text }
      | InspectionNotInclude : { key : Text, value : Text }
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
          , ValidityInDaysCompareExpr =
              \(c : { op : CompareOp, value : Text }) ->
                toMap
                  { validity_in_days =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALRubyExpr c.value }
                  }
          , ValidityInDaysCompareTypedExpr =
              \(c : { op : CompareOp, value : Expr }) ->
                toMap
                  { validity_in_days =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALExpr c.value }
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

-- Phase 3 attribute encoders -------------------------------------------------

let lxcStateAttrs =
      \(s : LxcState) ->
        merge
          { Exist   = toMap { exist   = AttrValue.AVBool True }
          , Running = toMap { running = AttrValue.AVBool True }
          }
          s

let mailAliasStateAttrs =
      \(s : MailAliasState) ->
        merge
          { AliasedTo =
              \(r : Text) -> toMap { aliased_to = AttrValue.AVText r }
          }
          s

let ppaStateAttrs =
      \(s : PpaState) ->
        merge
          { Exist   = toMap { exist   = AttrValue.AVBool True }
          , Enabled = toMap { enabled = AttrValue.AVBool True }
          }
          s

let yumrepoStateAttrs =
      \(s : YumrepoState) ->
        merge
          { Exist   = toMap { exist   = AttrValue.AVBool True }
          , Enabled = toMap { enabled = AttrValue.AVBool True }
          }
          s

let iisAppPoolStateAttrs =
      \(s : IisAppPoolState) ->
        merge
          { Exist            = toMap { exist = AttrValue.AVBool True }
          , HasDotnetVersion =
              \(v : Text) -> toMap { dotnet_version = AttrValue.AVText v }
          }
          s

let iisWebsiteStateAttrs =
      \(s : IisWebsiteState) ->
        merge
          { Exist           = toMap { exist   = AttrValue.AVBool True }
          , Enabled         = toMap { enabled = AttrValue.AVBool True }
          , Running         = toMap { running = AttrValue.AVBool True }
          , InAppPool       =
              \(p : Text) -> toMap { in_app_pool   = AttrValue.AVText p }
          , HasPhysicalPath =
              \(p : Text) -> toMap { physical_path = AttrValue.AVText p }
          }
          s

let mysqlConfigStateAttrs =
      \(s : MysqlConfigState) ->
        merge
          { EqText =
              \(t : Text) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = CompareOp.Eq, value = AttrLeaf.ALText t }
                  }
          , EqNat =
              \(n : Natural) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = CompareOp.Eq, value = AttrLeaf.ALNat n }
                  }
          , Compare =
              \(c : { op : CompareOp, value : Natural }) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALNat c.value }
                  }
          , CompareExpr =
              \(c : { op : CompareOp, value : Text }) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALRubyExpr c.value }
                  }
          , CompareTypedExpr =
              \(c : { op : CompareOp, value : Expr }) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALExpr c.value }
                  }
          }
          s

let phpConfigStateAttrs =
      \(s : PhpConfigState) ->
        merge
          { EqText =
              \(t : Text) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = CompareOp.Eq, value = AttrLeaf.ALText t }
                  }
          , EqNat =
              \(n : Natural) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = CompareOp.Eq, value = AttrLeaf.ALNat n }
                  }
          , Compare =
              \(c : { op : CompareOp, value : Natural }) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALNat c.value }
                  }
          , CompareExpr =
              \(c : { op : CompareOp, value : Text }) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALRubyExpr c.value }
                  }
          , CompareTypedExpr =
              \(c : { op : CompareOp, value : Expr }) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = c.op, value = AttrLeaf.ALExpr c.value }
                  }
          , Match =
              \(p : Text) ->
                toMap
                  { value =
                      AttrValue.AVCompare
                        { op = CompareOp.Match, value = AttrLeaf.ALRegex p }
                  }
          }
          s

let x509PrivateKeyStateAttrs =
      \(s : X509PrivateKeyState) ->
        merge
          { Encrypted    = toMap { encrypted     = AttrValue.AVBool True }
          , NotEncrypted = toMap { not_encrypted = AttrValue.AVBool True }
          , Valid        = toMap { valid         = AttrValue.AVBool True }
          , HasMatchingCertificate =
              \(p : Text) ->
                toMap { matching_certificate = AttrValue.AVText p }
          }
          s

let zfsStateAttrs =
      \(s : ZfsState) ->
        merge
          { Exist = toMap { exist = AttrValue.AVBool True }
          , HasProperty =
              \(rec : List { mapKey : Text, mapValue : Text }) ->
                toMap
                  { property =
                      AttrValue.AVRecord (textRecToAttrLeafRec rec)
                  }
          }
          s

-- docker_container is a mixed-wildcard kind: known attr keys (exist/running/
-- volume) are typed in the schema; inspect/inspect_include/inspection_not_include
-- prefixed keys are accepted as wildcards. The Dhall encoder produces those
-- prefix-tagged keys directly so the emitter can recover the original semantics.
let dockerContainerStateAttrs =
      \(s : DockerContainerState) ->
        merge
          { Exist   = toMap { exist   = AttrValue.AVBool True }
          , Running = toMap { running = AttrValue.AVBool True }
          , HasVolume =
              \(v : { containerPath : Text, hostPath : Text }) ->
                toMap
                  { volume =
                      AttrValue.AVList
                        [ AttrLeaf.ALText v.containerPath
                        , AttrLeaf.ALText v.hostPath
                        ]
                  }
          , InspectEqText =
              \(p : { keyPath : Text, value : Text }) ->
                [ { mapKey = "inspect:" ++ p.keyPath
                  , mapValue = AttrValue.AVText p.value
                  }
                ]
          , InspectEqNat =
              \(p : { keyPath : Text, value : Natural }) ->
                [ { mapKey = "inspect:" ++ p.keyPath
                  , mapValue = AttrValue.AVNat p.value
                  }
                ]
          , InspectEqBool =
              \(p : { keyPath : Text, value : Bool }) ->
                [ { mapKey = "inspect:" ++ p.keyPath
                  , mapValue = AttrValue.AVBool p.value
                  }
                ]
          , InspectEqSymbol =
              \(p : { keyPath : Text, value : Text }) ->
                [ { mapKey = "inspect:" ++ p.keyPath
                  , mapValue = AttrValue.AVSymbol p.value
                  }
                ]
          , InspectInclude =
              \(p : { keyPath : Text, value : Text }) ->
                [ { mapKey = "inspect_include:" ++ p.keyPath
                  , mapValue = AttrValue.AVText p.value
                  }
                ]
          , InspectionNotInclude =
              \(p : { key : Text, value : Text }) ->
                [ { mapKey = "inspection_not_include:" ++ p.key
                  , mapValue = AttrValue.AVText p.value
                  }
                ]
          }
          s

let dockerImageStateAttrs =
      \(s : DockerImageState) ->
        merge
          { Exist = toMap { exist = AttrValue.AVBool True }
          , InspectEqText =
              \(p : { keyPath : Text, value : Text }) ->
                [ { mapKey = "inspect:" ++ p.keyPath
                  , mapValue = AttrValue.AVText p.value
                  }
                ]
          , InspectEqNat =
              \(p : { keyPath : Text, value : Natural }) ->
                [ { mapKey = "inspect:" ++ p.keyPath
                  , mapValue = AttrValue.AVNat p.value
                  }
                ]
          , InspectEqBool =
              \(p : { keyPath : Text, value : Bool }) ->
                [ { mapKey = "inspect:" ++ p.keyPath
                  , mapValue = AttrValue.AVBool p.value
                  }
                ]
          , InspectEqSymbol =
              \(p : { keyPath : Text, value : Text }) ->
                [ { mapKey = "inspect:" ++ p.keyPath
                  , mapValue = AttrValue.AVSymbol p.value
                  }
                ]
          , InspectInclude =
              \(p : { keyPath : Text, value : Text }) ->
                [ { mapKey = "inspect_include:" ++ p.keyPath
                  , mapValue = AttrValue.AVText p.value
                  }
                ]
          , InspectionNotInclude =
              \(p : { key : Text, value : Text }) ->
                [ { mapKey = "inspection_not_include:" ++ p.key
                  , mapValue = AttrValue.AVText p.value
                  }
                ]
          }
          s

-- Smart constructors --------------------------------------------------------

let service
    : Text -> ServiceState -> Assertion
    = \(name : Text) ->
      \(s : ServiceState) ->
        { kind = "service", primaryKey = name, attrs = serviceStateAttrs s, module = None Text }

let package
    : Text -> PackageState -> Assertion
    = \(name : Text) ->
      \(s : PackageState) ->
        { kind = "package", primaryKey = name, attrs = packageStateAttrs s, module = None Text }

let port
    : Natural -> PortState -> Assertion
    = \(p : Natural) ->
      \(s : PortState) ->
        { kind = "port", primaryKey = Natural/show p, attrs = portStateAttrs s, module = None Text }

let file
    : Text -> FileState -> Assertion
    = \(path : Text) ->
      \(s : FileState) ->
        { kind = "file", primaryKey = path, attrs = fileStateAttrs s, module = None Text }

let command
    : Text -> CommandState -> Assertion
    = \(cmd : Text) ->
      \(s : CommandState) ->
        { kind = "command", primaryKey = cmd, attrs = commandStateAttrs s, module = None Text }

let user
    : Text -> UserState -> Assertion
    = \(name : Text) ->
      \(s : UserState) ->
        { kind = "user", primaryKey = name, attrs = userStateAttrs s, module = None Text }

let group
    : Text -> GroupState -> Assertion
    = \(name : Text) ->
      \(s : GroupState) ->
        { kind = "group", primaryKey = name, attrs = groupStateAttrs s, module = None Text }

let process
    : Text -> ProcessState -> Assertion
    = \(name : Text) ->
      \(s : ProcessState) ->
        { kind = "process", primaryKey = name, attrs = processStateAttrs s, module = None Text }

let mount
    : Text -> MountState -> Assertion
    = \(path : Text) ->
      \(s : MountState) ->
        { kind = "mount", primaryKey = path, attrs = mountStateAttrs s, module = None Text }

let interface
    : Text -> InterfaceState -> Assertion
    = \(name : Text) ->
      \(s : InterfaceState) ->
        { kind = "interface", primaryKey = name, attrs = interfaceStateAttrs s, module = None Text }

let kernelModule
    : Text -> KernelModuleState -> Assertion
    = \(name : Text) ->
      \(s : KernelModuleState) ->
        { kind = "kernel-module", primaryKey = name, attrs = kernelModuleStateAttrs s, module = None Text }

let bond
    : Text -> BondState -> Assertion
    = \(name : Text) ->
      \(s : BondState) ->
        { kind = "bond", primaryKey = name, attrs = bondStateAttrs s, module = None Text }

let bridge
    : Text -> BridgeState -> Assertion
    = \(name : Text) ->
      \(s : BridgeState) ->
        { kind = "bridge", primaryKey = name, attrs = bridgeStateAttrs s, module = None Text }

-- defaultGateway is a singleton: takes no Text argument; primaryKey is fixed
-- to the kind name to satisfy non-empty validation. The emitter omits the
-- (<primaryKey>) argument from the generated `describe` block.
let defaultGateway
    : DefaultGatewayState -> Assertion
    = \(s : DefaultGatewayState) ->
        { kind = "default_gateway"
        , primaryKey = "default_gateway"
        , attrs = defaultGatewayStateAttrs s
        , module = None Text
        }

let host
    : Text -> HostState -> Assertion
    = \(name : Text) ->
      \(s : HostState) ->
        { kind = "host", primaryKey = name, attrs = hostStateAttrs s, module = None Text }

let ip6tables
    : Text -> Ip6tablesState -> Assertion
    = \(table : Text) ->
      \(s : Ip6tablesState) ->
        { kind = "ip6tables", primaryKey = table, attrs = ip6tablesStateAttrs s, module = None Text }

let ipfilter
    : Text -> IpfilterState -> Assertion
    = \(label : Text) ->
      \(s : IpfilterState) ->
        { kind = "ipfilter", primaryKey = label, attrs = ipfilterStateAttrs s, module = None Text }

let ipnat
    : Text -> IpnatState -> Assertion
    = \(label : Text) ->
      \(s : IpnatState) ->
        { kind = "ipnat", primaryKey = label, attrs = ipnatStateAttrs s, module = None Text }

let iptables
    : Text -> IptablesState -> Assertion
    = \(table : Text) ->
      \(s : IptablesState) ->
        { kind = "iptables", primaryKey = table, attrs = iptablesStateAttrs s, module = None Text }

-- routingTable is a singleton (no primary key); each HasEntry attaches one
-- destination/gateway pair to the same describe block.
let routingTable
    : RoutingTableState -> Assertion
    = \(s : RoutingTableState) ->
        { kind = "routing_table"
        , primaryKey = "routing_table"
        , attrs = routingTableStateAttrs s
        , module = None Text
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
        , module = None Text
        }

let selinuxModule
    : Text -> SelinuxModuleState -> Assertion
    = \(name : Text) ->
      \(s : SelinuxModuleState) ->
        { kind = "selinux_module"
        , primaryKey = name
        , attrs = selinuxModuleStateAttrs s
        , module = None Text
        }

let linuxAuditSystem
    : LinuxAuditSystemState -> Assertion
    = \(s : LinuxAuditSystemState) ->
        { kind = "linux_audit_system"
        , primaryKey = "linux_audit_system"
        , attrs = linuxAuditSystemStateAttrs s
        , module = None Text
        }

let linuxKernelParameter
    : Text -> LinuxKernelParameterState -> Assertion
    = \(name : Text) ->
      \(s : LinuxKernelParameterState) ->
        { kind = "linux_kernel_parameter"
        , primaryKey = name
        , attrs = linuxKernelParameterStateAttrs s
        , module = None Text
        }

let cgroup
    : Text -> CgroupState -> Assertion
    = \(name : Text) ->
      \(s : CgroupState) ->
        { kind = "cgroup", primaryKey = name, attrs = cgroupStateAttrs s, module = None Text }

let windowsFeature
    : Text -> WindowsFeatureState -> Assertion
    = \(name : Text) ->
      \(s : WindowsFeatureState) ->
        { kind = "windows_feature"
        , primaryKey = name
        , attrs = windowsFeatureStateAttrs s
        , module = None Text
        }

-- cron is a singleton: there is only one cron table per host.
let cron
    : CronState -> Assertion
    = \(s : CronState) ->
        { kind = "cron"
        , primaryKey = "cron"
        , attrs = cronStateAttrs s
        , module = None Text
        }

let x509Certificate
    : Text -> X509CertificateState -> Assertion
    = \(path : Text) ->
      \(s : X509CertificateState) ->
        { kind = "x509_certificate"
        , primaryKey = path
        , attrs = x509CertificateStateAttrs s
        , module = None Text
        }

let windowsRegistryKey
    : Text -> WindowsRegistryKeyState -> Assertion
    = \(path : Text) ->
      \(s : WindowsRegistryKeyState) ->
        { kind = "windows_registry_key"
        , primaryKey = path
        , attrs = windowsRegistryKeyStateAttrs s
        , module = None Text
        }

-- Phase 3 smart constructors -------------------------------------------------

let lxc
    : Text -> LxcState -> Assertion
    = \(name : Text) ->
      \(s : LxcState) ->
        { kind = "lxc", primaryKey = name, attrs = lxcStateAttrs s, module = None Text }

let mailAlias
    : Text -> MailAliasState -> Assertion
    = \(name : Text) ->
      \(s : MailAliasState) ->
        { kind = "mail_alias", primaryKey = name, attrs = mailAliasStateAttrs s, module = None Text }

let ppa
    : Text -> PpaState -> Assertion
    = \(name : Text) ->
      \(s : PpaState) ->
        { kind = "ppa", primaryKey = name, attrs = ppaStateAttrs s, module = None Text }

let yumrepo
    : Text -> YumrepoState -> Assertion
    = \(name : Text) ->
      \(s : YumrepoState) ->
        { kind = "yumrepo", primaryKey = name, attrs = yumrepoStateAttrs s, module = None Text }

let iisAppPool
    : Text -> IisAppPoolState -> Assertion
    = \(name : Text) ->
      \(s : IisAppPoolState) ->
        { kind = "iis_app_pool"
        , primaryKey = name
        , attrs = iisAppPoolStateAttrs s
        , module = None Text
        }

let iisWebsite
    : Text -> IisWebsiteState -> Assertion
    = \(name : Text) ->
      \(s : IisWebsiteState) ->
        { kind = "iis_website"
        , primaryKey = name
        , attrs = iisWebsiteStateAttrs s
        , module = None Text
        }

let mysqlConfig
    : Text -> MysqlConfigState -> Assertion
    = \(name : Text) ->
      \(s : MysqlConfigState) ->
        { kind = "mysql_config"
        , primaryKey = name
        , attrs = mysqlConfigStateAttrs s
        , module = None Text
        }

-- phpConfig: single-arg form. The describe block becomes
-- @describe php_config('default_mimetype') do@.
let phpConfig
    : Text -> PhpConfigState -> Assertion
    = \(name : Text) ->
      \(s : PhpConfigState) ->
        { kind = "php_config"
        , primaryKey = name
        , attrs = phpConfigStateAttrs s
        , module = None Text
        }

-- phpConfigWithIni: two-arg form. The encoder injects an extra @_ini@
-- attribute that the emitter consumes during header generation to produce
-- @describe php_config('display_errors', :ini => '/etc/php/7.1/fpm/php.ini') do@.
let phpConfigWithIni
    : Text -> Text -> PhpConfigState -> Assertion
    = \(name : Text) ->
      \(iniPath : Text) ->
      \(s : PhpConfigState) ->
        { kind = "php_config"
        , primaryKey = name
        , attrs =
            phpConfigStateAttrs s
              # [ { mapKey = "_ini"
                  , mapValue = AttrValue.AVText iniPath
                  }
                ]
        , module = None Text
        }

let x509PrivateKey
    : Text -> X509PrivateKeyState -> Assertion
    = \(path : Text) ->
      \(s : X509PrivateKeyState) ->
        { kind = "x509_private_key"
        , primaryKey = path
        , attrs = x509PrivateKeyStateAttrs s
        , module = None Text
        }

let zfs
    : Text -> ZfsState -> Assertion
    = \(name : Text) ->
      \(s : ZfsState) ->
        { kind = "zfs", primaryKey = name, attrs = zfsStateAttrs s, module = None Text }

let dockerContainer
    : Text -> DockerContainerState -> Assertion
    = \(name : Text) ->
      \(s : DockerContainerState) ->
        { kind = "docker_container"
        , primaryKey = name
        , attrs = dockerContainerStateAttrs s
        , module = None Text
        }

let dockerImage
    : Text -> DockerImageState -> Assertion
    = \(name : Text) ->
      \(s : DockerImageState) ->
        { kind = "docker_image"
        , primaryKey = name
        , attrs = dockerImageStateAttrs s
        , module = None Text
        }

-- | Expand an Inventory custom-attribute @name@ into the Ruby variable name
-- the emitter binds at the top of the generated spec file. Plans that need
-- to reference a per-host dynamic value should write
-- @expand_attr "mem_total_bytes"@ instead of hard-coding
-- @"paninfraspec_mem_total_bytes"@: the prefix is owned by the generator and
-- may change.
let expand_attr
    : Text -> Text
    = \(name : Text) -> "paninfraspec_" ++ name

-- | Typed equivalent of @expand_attr "n" ++ ".to_i"@. Renders to
-- @paninfraspec_<name>.to_i@.
let factInt
    : Text -> Expr
    = \(name : Text) -> Expr.FactInt name

-- | Typed equivalent of @expand_attr "n" ++ ".to_i * m1 * m2 ... / d"@.
-- Multipliers are applied left-to-right then divided once. Use this for
-- per-host arithmetic patterns (memory %, unit conversions) that would
-- otherwise be written as a string-embedded Ruby fragment via
-- @CompareExpr@.
let factIntScaled
    : Text -> List Natural -> Natural -> Expr
    = \(name : Text) ->
      \(muls : List Natural) ->
      \(divisor : Natural) ->
        Expr.FactIntScaled
          { name = name, muls = muls, divisor = divisor }

-- | Operand smart constructors for the binary `Add`/`Sub`/`Mul`/`Div`
-- expression shapes.
let opLit
    : Natural -> Operand
    = \(n : Natural) -> Operand.Lit n

let opFact
    : Text -> Operand
    = \(name : Text) -> Operand.Fact name

-- | Two-operand arithmetic. Each operand is either a numeric literal
-- (`opLit`) or a host customAttribute reference (`opFact`); both render
-- as Ruby atoms so no parens are emitted at the join.
let exprAdd
    : Operand -> Operand -> Expr
    = \(a : Operand) -> \(b : Operand) -> Expr.Add { left = a, right = b }

let exprSub
    : Operand -> Operand -> Expr
    = \(a : Operand) -> \(b : Operand) -> Expr.Sub { left = a, right = b }

let exprMul
    : Operand -> Operand -> Expr
    = \(a : Operand) -> \(b : Operand) -> Expr.Mul { left = a, right = b }

let exprDiv
    : Operand -> Operand -> Expr
    = \(a : Operand) -> \(b : Operand) -> Expr.Div { left = a, right = b }

-- | Sugar for the common "@N%@ of host fact" ratio pattern.
-- @percentOf 70 "total_ram_kb"@ expands to
-- @paninfraspec_total_ram_kb.to_i * 70 / 100@.
let percentOf
    : Natural -> Text -> Expr
    = \(percent : Natural) ->
      \(name : Text) ->
        Expr.FactIntScaled
          { name = name, muls = [percent], divisor = 100 }

-- | Tag every assertion in the list with a product label. The emitter then
-- groups assertions by label so a single host can produce multiple spec
-- files (e.g. @Web/nginx_spec.rb@ and @Web/php_spec.rb@). Module-aware
-- splitting requires a v2 Layout; with a v1 Layout all modules collapse
-- back into one file (the pre-module behaviour).
--
-- `List/map` is not a Dhall built-in so the implementation here uses
-- `List/fold` to keep the prelude import-free.
let module_
    : Text -> List Assertion -> List Assertion
    = \(name : Text) ->
      \(xs   : List Assertion) ->
        List/fold
          Assertion
          xs
          (List Assertion)
          ( \(a   : Assertion) ->
            \(acc : List Assertion) ->
              [ a // { module = Some name } ] # acc
          )
          ([] : List Assertion)

in  { AttrValue         = AttrValue
    , AttrLeaf          = AttrLeaf
    , Expr              = Expr
    , Operand           = Operand
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
    -- Phase 3: serverspec.org coverage completion
    , LxcState              = LxcState
    , MailAliasState        = MailAliasState
    , PpaState              = PpaState
    , YumrepoState          = YumrepoState
    , IisAppPoolState       = IisAppPoolState
    , IisWebsiteState       = IisWebsiteState
    , MysqlConfigState      = MysqlConfigState
    , PhpConfigState        = PhpConfigState
    , X509PrivateKeyState   = X509PrivateKeyState
    , ZfsState              = ZfsState
    , DockerContainerState  = DockerContainerState
    , DockerImageState      = DockerImageState
    , lxc                   = lxc
    , mailAlias             = mailAlias
    , ppa                   = ppa
    , yumrepo               = yumrepo
    , iisAppPool            = iisAppPool
    , iisWebsite            = iisWebsite
    , mysqlConfig           = mysqlConfig
    , phpConfig             = phpConfig
    , phpConfigWithIni      = phpConfigWithIni
    , x509PrivateKey        = x509PrivateKey
    , zfs                   = zfs
    , dockerContainer       = dockerContainer
    , dockerImage           = dockerImage
    -- Custom-attribute references (Inventory.customAttributes)
    , expand_attr          = expand_attr
    -- Typed expression IR (issue #57): preferred over `expand_attr`
    -- string-concat for the most common per-host arithmetic patterns.
    , factInt              = factInt
    , factIntScaled        = factIntScaled
    , percentOf            = percentOf
    -- Operand smart constructors and binary arithmetic over Operands.
    , opLit                = opLit
    , opFact               = opFact
    , exprAdd              = exprAdd
    , exprSub              = exprSub
    , exprMul              = exprMul
    , exprDiv              = exprDiv
    -- Product-label wrapper that tags assertions for per-module file split
    -- (`module` is a Dhall reserved-ish word in some preludes, so the field
    -- name uses an underscore suffix; users invoke it as `Spec.module_`).
    , module_              = module_
    , targetBackend     = "serverspec"
    }
