# Resource catalogue

The Dhall prelude in [`dhall/Serverspec.dhall`](../dhall/Serverspec.dhall)
exposes the following smart constructors. Each one takes a primary key (the
service name, port number, file path, etc.) and a state value drawn from the
matching `*State` union.

| Resource | Constructor | States |
|---|---|---|
| Service | `service : Text -> ServiceState -> Assertion` | `Running`, `Enabled` |
| Package | `package : Text -> PackageState -> Assertion` | `Installed` |
| Port | `port : Natural -> PortState -> Assertion` | `Listening`, `WithProtocol : Text` |
| Command | `command : Text -> CommandState -> Assertion` | `ExitCode : Natural` |
| File | `file : Text -> FileState -> Assertion` | `Exist`, `OwnedBy : Text`, `GroupedInto : Text`, `Mode : Natural`, `Contains : Text` |
| User | `user : Text -> UserState -> Assertion` | `Exist`, `HasUid : Natural`, `BelongsToGroup : Text`, `HasHomeDirectory : Text`, `HasLoginShell : Text` |
| Group | `group : Text -> GroupState -> Assertion` | `Exist`, `HasGid : Natural` |
| Process | `process : Text -> ProcessState -> Assertion` | `Running`, `RunByUser : Text` |
| Mount | `mount : Text -> MountState -> Assertion` | `Mounted`, `OnDevice : Text`, `OfFstype : Text` |
| Interface | `interface : Text -> InterfaceState -> Assertion` | `Exist`, `HasSpeed : Natural`, `HasIpv4Address : Text` |
| Kernel module | `kernelModule : Text -> KernelModuleState -> Assertion` | `Loaded` |
| Bond | `bond : Text -> BondState -> Assertion` | `Exist`, `HasInterface : Text` |
| Bridge | `bridge : Text -> BridgeState -> Assertion` | `Exist`, `HasInterface : Text` |
| Default gateway (singleton) | `defaultGateway : DefaultGatewayState -> Assertion` | `HasIpaddress : Text`, `HasInterface : Text` |
| Host | `host : Text -> HostState -> Assertion` | `Resolvable`, `Reachable`, `HasIpaddress : Text` |
| iptables | `iptables : Text -> IptablesState -> Assertion` | `HasRule : Text` |
| ip6tables | `ip6tables : Text -> Ip6tablesState -> Assertion` | `HasRule : Text` |
| ipfilter | `ipfilter : Text -> IpfilterState -> Assertion` | `HasRule : Text` |
| ipnat | `ipnat : Text -> IpnatState -> Assertion` | `HasRule : Text` |
| Routing table (singleton) | `routingTable : RoutingTableState -> Assertion` | `HasEntry : { destination : Text, gateway : Text }` |
| SELinux (singleton) | `selinux : SelinuxState -> Assertion` | `Enforcing`, `Permissive`, `Disabled` |
| SELinux module | `selinuxModule : Text -> SelinuxModuleState -> Assertion` | `Enabled`, `Installed` |
| Linux audit system (singleton) | `linuxAuditSystem : LinuxAuditSystemState -> Assertion` | `Running`, `Enabled` |
| Linux kernel parameter | `linuxKernelParameter : Text -> LinuxKernelParameterState -> Assertion` | `HasValue : Text` |
| Cgroup | `cgroup : Text -> CgroupState -> Assertion` | `HasParameter : { name : Text, value : Text }` |

To express more than one state for the same resource (e.g. nginx must be both
running and enabled), write two assertions with the same primary key — they
are merged into a single `describe` block in the generated Ruby.

To add a new resource, extend `dhall/Serverspec.dhall` with a smart
constructor and a state type, then add one entry to `formatItLine` in
`src/PanInfraSpec/Emit/Serverspec.hs` mapping each attribute key to its Ruby
DSL line.

## Per-host dynamic thresholds

`MysqlConfigState`, `PhpConfigState`, and `X509CertificateState` each
expose a `Compare` family for comparing an attribute against a value:

| Constructor | Value type | Notes |
|---|---|---|
| `Compare`                | `Natural`   | Static threshold. |
| `CompareExpr`            | `Text`      | Escape hatch — emitted as bare Ruby. See [`docs/plan.md`](./plan.md#escape-hatch-compareexpr--expand_attr). |
| `CompareTypedExpr`       | `Spec.Expr` | Typed sub-IR; preferred when the pattern fits (see [`docs/plan.md`](./plan.md#typed-expression-path-preferred)). |

`X509CertificateState` uses the same shape under the
`ValidityInDaysCompare` / `ValidityInDaysCompareExpr` /
`ValidityInDaysCompareTypedExpr` names.
