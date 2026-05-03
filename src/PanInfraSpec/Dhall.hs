module PanInfraSpec.Dhall
  ( loadInventory
  , loadPlan
  , validate
  , backendAllowedKinds
  , knownBackends
  ) where

import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Dhall

import PanInfraSpec.IR

-- | Load the inventory file via Dhall and decode to @[Node]@.
loadInventory :: FilePath -> IO [Node]
loadInventory = Dhall.inputFile Dhall.auto

-- | Load the plan file via Dhall and decode to a 'PlanFile' record. The
-- record carries @targetBackend@ forwarded from the imported per-backend
-- prelude so the CLI can compare it against @--target@.
loadPlan :: FilePath -> IO PlanFile
loadPlan = Dhall.inputFile Dhall.auto

-- | Backends recognised by this build. Phase 1: @serverspec@ only.
knownBackends :: [Text]
knownBackends = ["serverspec"]

-- | Allowed @aKind@ values per backend. Acts as the layer-2 defence against
-- Smart Constructor 迂回 (a user hand-writing an Assertion record bypassing
-- the Dhall smart constructors).
backendAllowedKinds :: Text -> [Text]
backendAllowedKinds = \case
  "serverspec" ->
    [ "service", "package", "port", "file", "command"
    , "user", "group", "process", "mount", "interface", "kernel-module"
    , "bond", "bridge", "default_gateway", "host"
    , "ip6tables", "ipfilter", "ipnat", "iptables", "routing_table"
    , "selinux", "selinux_module", "linux_audit_system"
    , "linux_kernel_parameter", "cgroup"
    , "windows_feature", "windows_registry_key"
    , "x509_certificate", "cron"
    -- Phase 3: serverspec.org coverage completion
    , "lxc", "mail_alias", "ppa", "yumrepo"
    , "iis_app_pool", "iis_website"
    , "mysql_config", "php_config"
    , "x509_private_key", "zfs"
    , "docker_container", "docker_image"
    ]
  _            -> []

-- | Layer-2 validation: structural integrity + backend kind allowlist.
-- Layer 3 (attrs schema, conflict fail-safe) is the emitter's responsibility.
validate :: ExecutionPlan -> Either Text ExecutionPlan
validate ep
  | T.null (epTargetBackend ep) =
      Left "empty targetBackend"
  | epTargetBackend ep `notElem` knownBackends =
      Left ("unknown backend: " <> epTargetBackend ep)
  | Just bad <- find badAssertion allAs =
      Left ("empty kind or primaryKey at: " <> aPrimaryKey bad)
  | Just bad <- find unknownKind allAs =
      Left ("kind not allowed for backend " <> epTargetBackend ep <> ": " <> aKind bad)
  | otherwise = Right ep
  where
    allAs        = concatMap jAssertions (epJobs ep)
    allowed      = backendAllowedKinds (epTargetBackend ep)
    badAssertion a = T.null (aKind a) || T.null (aPrimaryKey a)
    unknownKind  a = aKind a `notElem` allowed
