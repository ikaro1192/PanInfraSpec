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

in  { AttrValue         = AttrValue
    , AttrLeaf          = AttrLeaf
    , CompareOp         = CompareOp
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
    , targetBackend     = "serverspec"
    }
