module PanInfraSpec.Emit.Serverspec
  ( emit
    -- * Schema (exported for property testing)
  , AttrTag (..)
  , serverspecSchema
  ) where

import Control.Monad (foldM, forM_, unless, when)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Function (on)
import Data.List (groupBy, sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Read as TR
import Numeric.Natural (Natural)
import Prettyprinter (Doc, hsep, indent, pretty, punctuate, vsep, (<+>))
import qualified Prettyprinter as PP
import Prettyprinter.Render.Text (renderStrict)

import PanInfraSpec.Scaffold (Scaffold (..), OutputFile (..), resolveBuiltinDerivers)
import PanInfraSpec.IR
import PanInfraSpec.Layout (Layout (..), Sharing (..), applySpecPath, validateLayoutPath)

-- | Schema tag for an 'AttrValue'. Used by layer-3 validation only.
data AttrTag
  = ATText | ATNat | ATBool
  | ATSymbol | ATList | ATRecord | ATCompare
  deriving stock (Eq, Show)

-- | Per-kind allowed @(attrKey, expected tag)@ table. Authoritative source of
-- truth for which assertions Serverspec can emit.
serverspecSchema :: Map Text (Map Text AttrTag)
serverspecSchema = Map.fromList
  [ ("service", Map.fromList
      [ ("running", ATBool), ("enabled", ATBool) ])
  , ("package", Map.fromList
      [ ("installed", ATBool) ])
  , ("port", Map.fromList
      [ ("listening", ATBool), ("protocol", ATText) ])
  , ("windows_feature", Map.fromList
      [ ("installed", ATBool), ("install_method", ATText) ])
  , ("cron", Map.fromList
      [ ("entry", ATText), ("entry_user", ATText) ])
  , ("x509_certificate", Map.fromList
      [ ("validity_in_days", ATCompare) ])
  , ("windows_registry_key", Map.fromList
      [ ("property_args", ATList), ("property_value_args", ATList) ])
  , ("file", Map.fromList
      [ ("exist",        ATBool)
      , ("owned_by",     ATText)
      , ("grouped_into", ATText)
      , ("mode",         ATNat)
      , ("contains",     ATText)
      -- Phase 2 follow-up: simple file-type matchers
      , ("file_type",        ATBool)
      , ("directory",        ATBool)
      , ("symlink",          ATBool)
      , ("socket",           ATBool)
      , ("pipe",             ATBool)
      , ("block_device",     ATBool)
      , ("character_device", ATBool)
      , ("immutable",        ATBool)
      -- Phase 2 follow-up: permission chain matchers
      , ("readable",            ATBool)
      , ("readable_by_scope",   ATSymbol)
      , ("readable_by_user",    ATText)
      , ("writable",            ATBool)
      , ("writable_by_scope",   ATSymbol)
      , ("writable_by_user",    ATText)
      , ("executable",          ATBool)
      , ("executable_by_scope", ATSymbol)
      , ("executable_by_user",  ATText)
      -- Phase 2 follow-up: contain chain matchers
      , ("contains_from",   ATText)
      , ("contains_to",     ATText)
      , ("contains_after",  ATText)
      , ("contains_before", ATText)
      -- Phase 2 follow-up: link / mounted matchers
      , ("linked_to",         ATText)
      , ("be_mounted",        ATBool)
      , ("mounted_with",      ATRecord)
      , ("mounted_only_with", ATRecord)
      ])
  , ("command", Map.fromList
      [ ("exit-status", ATNat) ])
  , ("user", Map.fromList
      [ ("exist",                    ATBool)
      , ("uid",                      ATNat)
      , ("belongs_to_group",         ATText)
      , ("home_directory",           ATText)
      , ("login_shell",              ATText)
      , ("belongs_to_primary_group", ATText)
      , ("authorized_key",           ATText)
      ])
  , ("group", Map.fromList
      [ ("exist", ATBool), ("gid", ATNat) ])
  , ("process", Map.fromList
      [ ("running", ATBool)
      , ("user",    ATText)
      , ("group",   ATText)
      , ("args",    ATText)
      , ("count",   ATNat)
      ])
  , ("mount", Map.fromList
      [ ("mounted", ATBool)
      , ("device",  ATText)
      , ("fstype",  ATText)
      ])
  , ("interface", Map.fromList
      [ ("exist",        ATBool)
      , ("speed",        ATNat)
      , ("ipv4_address", ATText)
      , ("up",           ATBool)
      , ("ipv6_address", ATText)
      ])
  , ("kernel-module", Map.fromList
      [ ("loaded", ATBool) ])
  , ("bond", Map.fromList
      [ ("exist", ATBool), ("interface", ATText) ])
  , ("bridge", Map.fromList
      [ ("exist", ATBool), ("interface", ATText) ])
  , ("default_gateway", Map.fromList
      [ ("ipaddress", ATText), ("interface", ATText) ])
  , ("host", Map.fromList
      [ ("resolvable",     ATBool)
      , ("reachable",      ATBool)
      , ("ipaddress",      ATText)
      , ("reachable_with", ATRecord)
      ])
  , ("ip6tables", Map.fromList [ ("rule", ATText) ])
  , ("ipfilter",  Map.fromList [ ("rule", ATText) ])
  , ("ipnat",     Map.fromList [ ("rule", ATText) ])
  , ("iptables",  Map.fromList [ ("rule", ATText) ])
  , ("routing_table", Map.empty)  -- wildcard kind: any AVText key allowed
  , ("selinux", Map.fromList
      [ ("enforcing",  ATBool)
      , ("permissive", ATBool)
      , ("disabled",   ATBool)
      ])
  , ("selinux_module", Map.fromList
      [ ("enabled",   ATBool)
      , ("installed", ATBool)
      , ("version",   ATText)
      ])
  , ("linux_audit_system", Map.fromList
      [ ("running", ATBool)
      , ("enabled", ATBool)
      ])
  , ("linux_kernel_parameter", Map.fromList
      [ ("value", ATText) ])
  , ("cgroup", Map.empty)  -- wildcard kind: dynamic parameter names
  -- Phase 3: serverspec.org coverage completion
  , ("lxc", Map.fromList
      [ ("exist", ATBool), ("running", ATBool) ])
  , ("mail_alias", Map.fromList
      [ ("aliased_to", ATText) ])
  , ("ppa", Map.fromList
      [ ("exist", ATBool), ("enabled", ATBool) ])
  , ("yumrepo", Map.fromList
      [ ("exist", ATBool), ("enabled", ATBool) ])
  , ("iis_app_pool", Map.fromList
      [ ("exist", ATBool), ("dotnet_version", ATText) ])
  , ("iis_website", Map.fromList
      [ ("exist",         ATBool)
      , ("enabled",       ATBool)
      , ("running",       ATBool)
      , ("in_app_pool",   ATText)
      , ("physical_path", ATText)
      ])
  , ("mysql_config", Map.fromList
      [ ("value", ATCompare) ])
  , ("php_config", Map.fromList
      [ ("value", ATCompare)
      , ("_ini",  ATText)  -- header injection sentinel; consumed by formatGroup
      ])
  , ("x509_private_key", Map.fromList
      [ ("encrypted",            ATBool)
      , ("not_encrypted",        ATBool)
      , ("valid",                ATBool)
      , ("matching_certificate", ATText)
      ])
  , ("zfs", Map.fromList
      [ ("exist",    ATBool)
      , ("property", ATRecord)
      ])
  , ("docker_container", Map.fromList
      [ ("exist",   ATBool)
      , ("running", ATBool)
      , ("volume",  ATList)
      ])
  , ("docker_image", Map.fromList
      [ ("exist", ATBool) ])
  ]

-- | Kinds whose @describe@ block takes no primary-key argument
-- (e.g. @describe selinux do ... end@). The Dhall smart constructor for these
-- kinds takes no @Text@ argument and stores the kind name as @primaryKey@ to
-- satisfy layer-2 non-empty validation.
singletonKinds :: Set Text
singletonKinds = Set.fromList
  [ "default_gateway"
  , "routing_table"
  , "selinux"
  , "linux_audit_system"
  , "cron"
  ]

-- | For wildcard kinds (those whose schema entry is empty), this table lists
-- which 'AttrTag's are accepted for any attr key. Defaults to @[ATText]@ when
-- a kind is not present, preserving the original wildcard behavior.
wildcardValueTags :: Map Text [AttrTag]
wildcardValueTags = Map.fromList
  [ ("routing_table", [ATText, ATRecord])
  , ("cgroup",        [ATText])
  ]

-- | Mixed-wildcard kinds: their schema lists known attr keys with fixed types,
-- but unknown keys are accepted as wildcard values matching the listed
-- 'AttrTag's. The Docker resources use this so @inspect:<keypath>@ /
-- @inspect_include:<keypath>@ / @inspection_not_include:<key>@ attribute keys
-- (whose suffix varies per inspection target) can flow through validation
-- without enumerating every possible Docker JSON path in the schema.
mixedWildcardKinds :: Map Text [AttrTag]
mixedWildcardKinds = Map.fromList
  [ ("docker_container", [ATText, ATNat, ATBool, ATSymbol])
  , ("docker_image",     [ATText, ATNat, ATBool, ATSymbol])
  ]

tagOf :: AttrValue -> AttrTag
tagOf = \case
  AVText    _   -> ATText
  AVNat     _   -> ATNat
  AVBool    _   -> ATBool
  AVSymbol  _   -> ATSymbol
  AVList    _   -> ATList
  AVRecord  _   -> ATRecord
  AVCompare _ _ -> ATCompare

showTag :: AttrTag -> Text
showTag = \case
  ATText    -> "Text"
  ATNat     -> "Natural"
  ATBool    -> "Bool"
  ATSymbol  -> "Symbol"
  ATList    -> "List"
  ATRecord  -> "Record"
  ATCompare -> "Compare"

showVal :: AttrValue -> Text
showVal = \case
  AVText    t   -> "AVText "    <> t
  AVNat     n   -> "AVNat "     <> T.pack (show n)
  AVBool    b   -> "AVBool "    <> T.pack (show b)
  AVSymbol  s   -> "AVSymbol "  <> s
  AVList    xs  -> "AVList "    <> T.pack (show xs)
  AVRecord  m   -> "AVRecord "  <> T.pack (show m)
  AVCompare o v -> "AVCompare " <> T.pack (show (o, v))

-- | Layer-3 validation: kind ∈ schema, attrs non-empty, every attr key ∈
-- schema for that kind, every attr value's tag matches the expected tag, and
-- per-kind primaryKey shape (port must be parseable as Natural).
validateAssertion :: Assertion -> Either Text Assertion
validateAssertion a@(Assertion k pk attrs _) = do
  kindSchema <- case Map.lookup k serverspecSchema of
    Just s  -> Right s
    Nothing -> Left ("unknown kind for serverspec: " <> k)
  when (Map.null attrs) $
    Left ("empty attrs for kind " <> k)
  forM_ (Map.toAscList attrs) $ \(key, val) ->
    if Map.null kindSchema
      then
        let allowed = Map.findWithDefault [ATText] k wildcardValueTags
            actual  = tagOf val
        in unless (actual `elem` allowed) $
             Left $ "wildcard kind " <> k <> " accepts "
                 <> T.intercalate "/" (map showTag allowed)
                 <> "; got " <> showTag actual <> " for key " <> key
      else case Map.lookup key kindSchema of
        Just expected -> do
          let actual = tagOf val
          unless (actual == expected) $
            Left $ "wrong attr type for " <> k <> "." <> key
                <> ": expected " <> showTag expected <> ", got " <> showTag actual
        Nothing -> case Map.lookup k mixedWildcardKinds of
          Just allowed ->
            let actual = tagOf val
            in unless (actual `elem` allowed) $
                 Left $ "mixed-wildcard kind " <> k <> " accepts "
                     <> T.intercalate "/" (map showTag allowed)
                     <> "; got " <> showTag actual <> " for key " <> key
          Nothing -> Left ("unknown attrs key for kind " <> k <> ": " <> key)
  when (k == "port") $
    case TR.decimal pk :: Either String (Natural, Text) of
      Right (_, rest) | T.null rest -> Right ()
      _ -> Left ("port primaryKey must be a natural number, got: " <> pk)
  pure a

-- | Group consecutive assertions sharing @(aKind, aPrimaryKey)@ after a stable
-- sort. The sort guarantees golden-test-stable output independent of the
-- assertion order in the input plan.
groupAssertions :: [Assertion] -> [NonEmpty Assertion]
groupAssertions = map NE.fromList
                . groupBy ((==) `on` groupKey)
                . sortOn groupKey
  where
    groupKey a = (aKind a, aPrimaryKey a)

-- | Merge a same-resource group into one 'Assertion'. Conflicting attribute
-- values trigger the layer-3 fail-safe so we never emit Ruby that's
-- guaranteed to fail at test time. Module labels are also consolidated:
-- two assertions sharing @(kind, primaryKey)@ but disagreeing on their
-- module label are rejected because the post-merge file split has nowhere
-- coherent to place the result.
mergeGroup :: NonEmpty Assertion -> Either Text Assertion
mergeGroup (a :| rest) = foldM step a rest
  where
    step acc nxt = do
      mergedAttrs  <- mergeAttrs  (aKind acc) (aPrimaryKey acc) (aAttrs  acc) (aAttrs  nxt)
      mergedModule <- mergeModule (aKind acc) (aPrimaryKey acc) (aModule acc) (aModule nxt)
      pure acc { aAttrs = mergedAttrs, aModule = mergedModule }

-- | Reject two assertions for the same @(kind, primaryKey)@ that disagree on
-- their module label. The user has to either align the labels, drop them,
-- or change the resource key — emitting the same describe block to two
-- product files is not a sensible default.
mergeModule
  :: Text -> Text -> Maybe Text -> Maybe Text -> Either Text (Maybe Text)
mergeModule _ _ a b | a == b = Right a
mergeModule k pk a b = Left $
  "conflicting module label for (" <> k <> ", " <> pk <> "): "
    <> showMod a <> " vs " <> showMod b
    <> " — assertions sharing a resource must agree on their module label or omit it"
  where
    showMod Nothing  = "(no module)"
    showMod (Just m) = m

mergeAttrs :: Text -> Text -> Map Text AttrValue -> Map Text AttrValue
           -> Either Text (Map Text AttrValue)
mergeAttrs k pk a b = foldM ins a (Map.toAscList b)
  where
    ins acc (key, val) = case Map.lookup key acc of
      Nothing -> Right (Map.insert key val acc)
      Just existing
        | existing == val -> Right acc
        | otherwise -> Left $
            "conflicting attribute " <> key <> " for (" <> k <> ", " <> pk <> "): "
            <> showVal existing <> " vs " <> showVal val

-- | Format the @primary key@ argument inside @describe X(...)@. Port emits an
-- integer literal; everything else emits a single-quoted, escaped string.
primaryDoc :: Text -> Text -> Either Text (Doc ann)
primaryDoc "port" pk = case TR.decimal pk :: Either String (Natural, Text) of
  Right (n, rest) | T.null rest -> Right (pretty n)
  _ -> Left ("port primaryKey must be a natural number, got: " <> pk)
primaryDoc _ pk = Right (rubyString pk)

-- | Emit a Ruby single-quoted string literal with @\\@ and @'@ escaped.
rubyString :: Text -> Doc ann
rubyString t = "'" <> pretty (escape t) <> "'"
  where
    escape = T.replace "'" "\\'" . T.replace "\\" "\\\\"

-- | One @it { ... }@ line. Total over schema-validated inputs; the catch-all
-- yields a visible error comment for any combination that bypasses validation.
formatItLine :: Text -> Text -> AttrValue -> Doc ann
-- service
formatItLine "service" "running"          _          = "it { should be_running }"
formatItLine "service" "enabled"          _          = "it { should be_enabled }"
-- package
formatItLine "package" "installed"        _          = "it { should be_installed }"
-- port
formatItLine "port"    "listening"        _          = "it { should be_listening }"
-- file
formatItLine "file"    "exist"            _          = "it { should exist }"
formatItLine "file"    "owned_by"         (AVText u) = "it { should be_owned_by " <> rubyString u <> " }"
formatItLine "file"    "grouped_into"     (AVText g) = "it { should be_grouped_into " <> rubyString g <> " }"
formatItLine "file"    "mode"             (AVNat n)  = "it { should be_mode " <> pretty n <> " }"
formatItLine "file"    "contains"         (AVText p) = "it { should contain " <> rubyString p <> " }"
-- file (Phase 2 follow-up: simple type matchers)
formatItLine "file"    "file_type"        _          = "it { should be_file }"
formatItLine "file"    "directory"        _          = "it { should be_directory }"
formatItLine "file"    "symlink"          _          = "it { should be_symlink }"
formatItLine "file"    "socket"           _          = "it { should be_socket }"
formatItLine "file"    "pipe"             _          = "it { should be_pipe }"
formatItLine "file"    "block_device"     _          = "it { should be_block_device }"
formatItLine "file"    "character_device" _          = "it { should be_character_device }"
formatItLine "file"    "immutable"        _          = "it { should be_immutable }"
-- file (Phase 2 follow-up: permission base flags + chain modifier fallbacks
-- so any single-key attr generated by property tests still emits valid Ruby)
formatItLine "file"    "readable"            _          = "it { should be_readable }"
formatItLine "file"    "readable_by_scope"   (AVSymbol s) =
  "it { should be_readable.by(:" <> pretty s <> ") }"
formatItLine "file"    "readable_by_user"    (AVText u) =
  "it { should be_readable.by_user(" <> rubyString u <> ") }"
formatItLine "file"    "writable"            _          = "it { should be_writable }"
formatItLine "file"    "writable_by_scope"   (AVSymbol s) =
  "it { should be_writable.by(:" <> pretty s <> ") }"
formatItLine "file"    "writable_by_user"    (AVText u) =
  "it { should be_writable.by_user(" <> rubyString u <> ") }"
formatItLine "file"    "executable"          _          = "it { should be_executable }"
formatItLine "file"    "executable_by_scope" (AVSymbol s) =
  "it { should be_executable.by(:" <> pretty s <> ") }"
formatItLine "file"    "executable_by_user"  (AVText u) =
  "it { should be_executable.by_user(" <> rubyString u <> ") }"
-- file (Phase 2 follow-up: contain chain modifier fallbacks)
formatItLine "file"    "contains_from"   (AVText p) =
  "it { should contain.from(" <> rubyString p <> ") }"
formatItLine "file"    "contains_to"     (AVText p) =
  "it { should contain.to(" <> rubyString p <> ") }"
formatItLine "file"    "contains_after"  (AVText p) =
  "it { should contain.after(" <> rubyString p <> ") }"
formatItLine "file"    "contains_before" (AVText p) =
  "it { should contain.before(" <> rubyString p <> ") }"
-- file (Phase 2 follow-up: link / mounted)
formatItLine "file"    "linked_to"  (AVText p) =
  "it { should be_linked_to " <> rubyString p <> " }"
formatItLine "file"    "be_mounted" _          = "it { should be_mounted }"
formatItLine "file"    "mounted_with"      (AVRecord kw) =
  "it { should be_mounted.with(" <> renderRecordKwargs kw <> ") }"
formatItLine "file"    "mounted_only_with" (AVRecord kw) =
  "it { should be_mounted.only_with(" <> renderRecordKwargs kw <> ") }"
-- command
formatItLine "command" "exit-status"      (AVNat n)  = "its(:exit_status) { should eq " <> pretty n <> " }"
-- user
formatItLine "user"    "exist"            _          = "it { should exist }"
formatItLine "user"    "uid"              (AVNat n)  = "it { should have_uid " <> pretty n <> " }"
formatItLine "user"    "belongs_to_group" (AVText g) = "it { should belong_to_group " <> rubyString g <> " }"
formatItLine "user"    "home_directory"   (AVText p) = "it { should have_home_directory " <> rubyString p <> " }"
formatItLine "user"    "login_shell"      (AVText s) = "it { should have_login_shell " <> rubyString s <> " }"
formatItLine "user"    "belongs_to_primary_group" (AVText g) =
  "it { should belong_to_primary_group " <> rubyString g <> " }"
formatItLine "user"    "authorized_key"   (AVText k) =
  "it { should have_authorized_key " <> rubyString k <> " }"
-- group
formatItLine "group"   "exist"            _          = "it { should exist }"
formatItLine "group"   "gid"              (AVNat n)  = "it { should have_gid " <> pretty n <> " }"
-- process
formatItLine "process" "running"          _          = "it { should be_running }"
formatItLine "process" "user"             (AVText u) = "its(:user) { should eq " <> rubyString u <> " }"
formatItLine "process" "group"            (AVText g) = "its(:group) { should eq " <> rubyString g <> " }"
formatItLine "process" "args"             (AVText a) = "its(:args) { should eq " <> rubyString a <> " }"
formatItLine "process" "count"            (AVNat n)  = "its(:count) { should eq " <> pretty n <> " }"
-- mount
formatItLine "mount"   "mounted"          _          = "it { should be_mounted }"
formatItLine "mount"   "device"           (AVText d) = "its(:device) { should eq " <> rubyString d <> " }"
formatItLine "mount"   "fstype"           (AVText t) = "its(:fstype) { should eq " <> rubyString t <> " }"
-- interface
formatItLine "interface" "exist"          _          = "it { should exist }"
formatItLine "interface" "speed"          (AVNat n)  = "its(:speed) { should eq " <> pretty n <> " }"
formatItLine "interface" "ipv4_address"   (AVText a) = "it { should have_ipv4_address " <> rubyString a <> " }"
formatItLine "interface" "up"             _          = "it { should be_up }"
formatItLine "interface" "ipv6_address"   (AVText a) = "it { should have_ipv6_address " <> rubyString a <> " }"
-- kernel-module
formatItLine "kernel-module" "loaded"     _          = "it { should be_loaded }"
-- bond
formatItLine "bond"      "exist"          _          = "it { should exist }"
formatItLine "bond"      "interface"      (AVText i) = "it { should have_interface " <> rubyString i <> " }"
-- bridge
formatItLine "bridge"    "exist"          _          = "it { should exist }"
formatItLine "bridge"    "interface"      (AVText i) = "it { should have_interface " <> rubyString i <> " }"
-- default_gateway (singleton)
formatItLine "default_gateway" "ipaddress" (AVText a) = "its(:ipaddress) { should eq " <> rubyString a <> " }"
formatItLine "default_gateway" "interface" (AVText i) = "its(:interface) { should eq " <> rubyString i <> " }"
-- host
formatItLine "host"      "resolvable"     _          = "it { should be_resolvable }"
formatItLine "host"      "reachable"      _          = "it { should be_reachable }"
formatItLine "host"      "ipaddress"      (AVText a) = "its(:ipaddress) { should eq " <> rubyString a <> " }"
-- iptables family
formatItLine "ip6tables" "rule"           (AVText r) = "it { should have_rule " <> rubyString r <> " }"
formatItLine "ipfilter"  "rule"           (AVText r) = "it { should have_rule " <> rubyString r <> " }"
formatItLine "ipnat"     "rule"           (AVText r) = "it { should have_rule " <> rubyString r <> " }"
formatItLine "iptables"  "rule"           (AVText r) = "it { should have_rule " <> rubyString r <> " }"
-- routing_table (wildcard schema, singleton): mapKey = destination CIDR, mapValue = gateway
formatItLine "routing_table" key          (AVText v) =
  "it { should have_entry :destination => " <> rubyString key
    <> ", :gateway => " <> rubyString v <> " }"
-- selinux (singleton): three mutually exclusive states
formatItLine "selinux"   "enforcing"      _          = "it { should be_enforcing }"
formatItLine "selinux"   "permissive"     _          = "it { should be_permissive }"
formatItLine "selinux"   "disabled"       _          = "it { should be_disabled }"
-- selinux_module
formatItLine "selinux_module" "enabled"   _          = "it { should be_enabled }"
formatItLine "selinux_module" "installed" _          = "it { should be_installed }"
-- linux_audit_system (singleton)
formatItLine "linux_audit_system" "running" _        = "it { should be_running }"
formatItLine "linux_audit_system" "enabled" _        = "it { should be_enabled }"
-- linux_kernel_parameter
formatItLine "linux_kernel_parameter" "value" (AVText v) =
  "its(:value) { should eq " <> rubyString v <> " }"
-- cgroup (wildcard schema): each attr key is a cgroup parameter name
formatItLine "cgroup"    key              (AVText v) =
  "its(" <> rubyString key <> ") { should eq " <> rubyString v <> " }"
-- Issue #3 follow-up matchers (single-key fallbacks; renderAttrs collapses
-- multi-key compounds before reaching here)
-- selinux_module.version (compound output if 'installed' sibling, falls back here otherwise)
formatItLine "selinux_module" "version" (AVText v) =
  "it { should be_installed.with_version(" <> rubyString v <> ") }"
-- host.reachable_with (single AVRecord)
formatItLine "host" "reachable_with" (AVRecord kw) =
  "it { should be_reachable.with(" <> renderRecordKwargs kw <> ") }"
-- windows_feature
formatItLine "windows_feature" "installed"      _          = "it { should be_installed }"
formatItLine "windows_feature" "install_method" (AVText m) =
  "it { should be_installed.by(" <> rubyString m <> ") }"
-- cron
formatItLine "cron" "entry"      (AVText e) = "it { should have_entry(" <> rubyString e <> ") }"
formatItLine "cron" "entry_user" (AVText u) = "it { should have_entry.with_user(" <> rubyString u <> ") }"
-- x509_certificate
formatItLine "x509_certificate" "validity_in_days" (AVCompare op leaf) =
  "its(:validity_in_days) { should " <> renderCompareRuby op (renderLeafRuby leaf) <> " }"
-- windows_registry_key
formatItLine "windows_registry_key" "property_args" (AVList xs) =
  "it { should have_property " <> renderArgList xs <> " }"
formatItLine "windows_registry_key" "property_value_args" (AVList xs) =
  "it { should have_property_value " <> renderArgList xs <> " }"
-- Phase 3 (serverspec.org coverage completion) -------------------------------
-- lxc
formatItLine "lxc"        "exist"          _          = "it { should exist }"
formatItLine "lxc"        "running"        _          = "it { should be_running }"
-- mail_alias
formatItLine "mail_alias" "aliased_to"     (AVText r) =
  "it { should be_aliased_to " <> rubyString r <> " }"
-- ppa
formatItLine "ppa"        "exist"          _          = "it { should exist }"
formatItLine "ppa"        "enabled"        _          = "it { should be_enabled }"
-- yumrepo
formatItLine "yumrepo"    "exist"          _          = "it { should exist }"
formatItLine "yumrepo"    "enabled"        _          = "it { should be_enabled }"
-- iis_app_pool
formatItLine "iis_app_pool" "exist"          _          = "it { should exist }"
formatItLine "iis_app_pool" "dotnet_version" (AVText v) =
  "it { should have_dotnet_version(" <> rubyString v <> ") }"
-- iis_website
formatItLine "iis_website" "exist"         _          = "it { should exist }"
formatItLine "iis_website" "enabled"       _          = "it { should be_enabled }"
formatItLine "iis_website" "running"       _          = "it { should be_running }"
formatItLine "iis_website" "in_app_pool"   (AVText p) =
  "it { should be_in_app_pool(" <> rubyString p <> ") }"
formatItLine "iis_website" "physical_path" (AVText p) =
  "it { should have_physical_path(" <> rubyString p <> ") }"
-- mysql_config / php_config: single value attr; renderAttrs handles the
-- normal compound flow. The single-key fallback below covers any future
-- code path that reaches formatItLine directly.
formatItLine "mysql_config" "value" (AVCompare op leaf) =
  "its(:value) { should " <> renderCompareRuby op (renderLeafRuby leaf) <> " }"
formatItLine "php_config"   "value" (AVCompare op leaf) =
  "its(:value) { should " <> renderCompareRuby op (renderLeafRuby leaf) <> " }"
-- x509_private_key
formatItLine "x509_private_key" "encrypted"     _          = "it { should be_encrypted }"
formatItLine "x509_private_key" "not_encrypted" _          = "it { should_not be_encrypted }"
formatItLine "x509_private_key" "valid"         _          = "it { should be_valid }"
formatItLine "x509_private_key" "matching_certificate" (AVText p) =
  "it { should have_matching_certificate(" <> rubyString p <> ") }"
-- zfs
formatItLine "zfs" "exist"    _              = "it { should exist }"
formatItLine "zfs" "property" (AVRecord kw)  =
  "it { should have_property " <> renderStringKwargs kw <> " }"
-- docker_container fixed-schema fallbacks. inspect:* keys are handled in
-- renderAttrs and never flow through here.
formatItLine "docker_container" "exist"   _ = "it { should exist }"
formatItLine "docker_container" "running" _ = "it { should be_running }"
formatItLine "docker_container" "volume"  (AVList xs) = case xs of
  [c, h] -> "it { should have_volume(" <> renderLeafRuby c <> ", "
              <> renderLeafRuby h <> ") }"
  _      -> "it { should have_volume " <> renderArgList xs <> " }"
-- docker_image fixed-schema fallback
formatItLine "docker_image" "exist" _ = "it { should exist }"
formatItLine k key _ =
  "# UNREACHABLE: unmatched (" <> pretty k <> ", " <> pretty key <> ")"

-- | Map an IR @kind@ to the Ruby resource name used inside @describe@. Most
-- kinds map identically; @kernel-module@ becomes @kernel_module@ to match
-- Serverspec's Ruby identifier.
kindToRubyResource :: Text -> Text
kindToRubyResource = \case
  "kernel-module" -> "kernel_module"
  k               -> k

-- | Render a single 'AttrLeaf' as a Ruby literal.
renderLeafRuby :: AttrLeaf -> Doc ann
renderLeafRuby = \case
  ALText     t -> rubyString t
  ALNat      n -> pretty n
  ALBool     b -> if b then "true" else "false"
  ALSymbol   s -> ":" <> pretty s
  ALRegex    p -> "/" <> pretty p <> "/"
  ALRubyExpr e -> pretty e

-- | Render a record as @:k => v, :k => v@ (Ruby keyword-arg syntax). Used
-- by @host.be_reachable.with@, @routing_table.have_entry@, etc.
renderRecordKwargs :: Map Text AttrLeaf -> Doc ann
renderRecordKwargs m =
  hsep $ punctuate ","
    [ ":" <> pretty k <+> "=>" <+> renderLeafRuby v
    | (k, v) <- Map.toAscList m
    ]

-- | Render a record as @'k' => v, 'k2' => v2@ (Ruby hash literal with string
-- keys). Used by @zfs.have_property@ and @docker_container.inspection_not_include@.
renderStringKwargs :: Map Text AttrLeaf -> Doc ann
renderStringKwargs m =
  hsep $ punctuate ","
    [ rubyString k <+> "=>" <+> renderLeafRuby v
    | (k, v) <- Map.toAscList m
    ]

-- | Render an 'AVList' as a Ruby positional argument list (no surrounding
-- parens). Used by @windows_registry_key.have_property@ etc.
renderArgList :: [AttrLeaf] -> Doc ann
renderArgList xs = hsep $ punctuate "," (map renderLeafRuby xs)

-- | Render a 'CompareOp' applied to a Ruby literal, suitable for the body
-- of a @should@ block. @OpEq@ becomes @eq N@; the others become @be > N@
-- etc., matching idiomatic Serverspec/RSpec.
renderCompareRuby :: CompareOp -> Doc ann -> Doc ann
renderCompareRuby op v = case op of
  OpEq    -> "eq" <+> v
  OpLt    -> "be" <+> "<"  <+> v
  OpLe    -> "be" <+> "<=" <+> v
  OpGt    -> "be" <+> ">"  <+> v
  OpGe    -> "be" <+> ">=" <+> v
  OpMatch -> "match" <+> v

-- | Render the @it { ... }@ lines of a @describe@ block. Indirection over
-- 'formatItLine' so that compound matchers can fold multiple attribute keys
-- into a single line by inspecting siblings via @attrs@.
renderAttrs :: Text -> Map Text AttrValue -> [Doc ann]
-- port: when @protocol@ is present, collapse it (and any sibling @listening@)
-- into a single @be_listening.with('proto')@ line. The @listening@ flag is
-- always implied by specifying a protocol, so it is always consumed here.
renderAttrs "port" attrs
  | Just (AVText proto) <- Map.lookup "protocol" attrs
  = "it { should be_listening.with(" <> rubyString proto <> ") }"
    : [ formatItLine "port" key val
      | (key, val) <- Map.toAscList (Map.delete "listening" (Map.delete "protocol" attrs))
      ]
-- selinux_module: collapse @{installed, version}@ into
-- @be_installed.with_version('x.y.z')@.
renderAttrs "selinux_module" attrs
  | Just (AVText v) <- Map.lookup "version" attrs
  = "it { should be_installed.with_version(" <> rubyString v <> ") }"
    : [ formatItLine "selinux_module" key val
      | (key, val) <- Map.toAscList
          (Map.delete "installed" (Map.delete "version" attrs))
      ]
-- host: collapse @{reachable, reachable_with}@ into
-- @be_reachable.with(:port=>22, :proto=>'tcp', ...)@.
renderAttrs "host" attrs
  | Just (AVRecord kw) <- Map.lookup "reachable_with" attrs
  = ("it { should be_reachable.with(" <> renderRecordKwargs kw <> ") }")
    : [ formatItLine "host" key val
      | (key, val) <- Map.toAscList
          (Map.delete "reachable" (Map.delete "reachable_with" attrs))
      ]
-- routing_table (wildcard schema): @AVText v@ keeps the existing 2-arg
-- @{:destination, :gateway}@ output; @AVRecord kw@ allows the 3+-arg form
-- (e.g. @{:destination, :gateway, :interface}@).
renderAttrs "routing_table" attrs =
  [ case val of
      AVRecord kw -> "it { should have_entry " <> renderRecordKwargs kw <> " }"
      _           -> formatItLine "routing_table" key val
  | (key, val) <- Map.toAscList attrs
  ]
-- windows_feature: @{installed, install_method}@ collapses into
-- @be_installed.by('dism')@.
renderAttrs "windows_feature" attrs
  | Just (AVText m) <- Map.lookup "install_method" attrs
  = "it { should be_installed.by(" <> rubyString m <> ") }"
    : [ formatItLine "windows_feature" key val
      | (key, val) <- Map.toAscList
          (Map.delete "installed" (Map.delete "install_method" attrs))
      ]
-- file (Phase 2 follow-up): collapse permission chains
-- (@be_readable.by_user('u')@, @be_writable.by(:owned)@ etc.), the contain
-- chain (@contain('p').from('a').to('b')@), and the mounted chain
-- (@be_mounted.with(:type=>'ext4')@). Each family's base flag (e.g.
-- @readable@, @contains@, @be_mounted@) is consumed when any of its
-- modifiers is present so the bare matcher is not double-emitted.
renderAttrs "file" attrs0 =
  let (containLines,    a1) = extractContainsChain          attrs0
      (executableLines, a2) = extractPermChain "executable" a1
      (mountedLines,    a3) = extractMountedChain           a2
      (readableLines,   a4) = extractPermChain "readable"   a3
      (writableLines,   a5) = extractPermChain "writable"   a4
      restLines = [ formatItLine "file" key val
                  | (key, val) <- Map.toAscList a5
                  ]
  in containLines
       ++ executableLines
       ++ mountedLines
       ++ readableLines
       ++ writableLines
       ++ restLines
-- cron: @{entry, entry_user}@ collapses into
-- @have_entry('...').with_user('root')@; @entry@ alone stays single.
renderAttrs "cron" attrs
  | Just (AVText e) <- Map.lookup "entry" attrs
  , Just (AVText u) <- Map.lookup "entry_user" attrs
  = ["it { should have_entry(" <> rubyString e
        <> ").with_user(" <> rubyString u <> ") }"]
  | Just (AVText e) <- Map.lookup "entry" attrs
  = ["it { should have_entry(" <> rubyString e <> ") }"]
-- x509_certificate: @AVCompare op (ALNat n)@ becomes @its(:k) { should be > N }@.
renderAttrs "x509_certificate" attrs
  | Just (AVCompare op leaf) <- Map.lookup "validity_in_days" attrs
  = ["its(:validity_in_days) { should "
        <> renderCompareRuby op (renderLeafRuby leaf) <> " }"]
-- windows_registry_key: each @AVList@ becomes a positional argument list
-- after @have_property@ / @have_property_value@.
renderAttrs "windows_registry_key" attrs =
  [ case (key, val) of
      ("property_args", AVList xs) ->
        "it { should have_property " <> renderArgList xs <> " }"
      ("property_value_args", AVList xs) ->
        "it { should have_property_value " <> renderArgList xs <> " }"
      _ -> formatItLine "windows_registry_key" key val
  | (key, val) <- Map.toAscList attrs
  ]
-- Docker resources use prefix-tagged attr keys to encode dynamic inspect
-- paths (@inspect:Path@, @inspect:HostConfig.NetworkMode@, etc.) without
-- adding a recursive AttrValue constructor. Strip the prefix here and emit
-- the corresponding Ruby. Fixed-schema keys (exist/running/volume) flow
-- through formatItLine.
renderAttrs "docker_container" attrs =
  [ renderDockerAttr "docker_container" key val | (key, val) <- Map.toAscList attrs ]
renderAttrs "docker_image" attrs =
  [ renderDockerAttr "docker_image" key val | (key, val) <- Map.toAscList attrs ]
renderAttrs k attrs =
  [ formatItLine k key val | (key, val) <- Map.toAscList attrs ]

-- | Phase 3: Docker prefix-tagged attribute renderer. Recognizes three
-- semantic prefixes for the inspect-family of matchers; falls back to
-- 'formatItLine' for fixed-schema keys.
renderDockerAttr :: Text -> Text -> AttrValue -> Doc ann
renderDockerAttr k key val
  | Just keyPath <- T.stripPrefix "inspect:" key =
      "its([" <> rubyString keyPath <> "]) { should eq "
        <> renderInspectScalar val <> " }"
  | Just keyPath <- T.stripPrefix "inspect_include:" key =
      "its([" <> rubyString keyPath <> "]) { should include "
        <> renderInspectScalar val <> " }"
  | Just hashKey <- T.stripPrefix "inspection_not_include:" key =
      case val of
        AVText v ->
          "its(:inspection) { should_not include "
            <> rubyString hashKey <> " => " <> rubyString v <> " }"
        _ -> formatItLine k key val
  | otherwise = formatItLine k key val

-- | Render a scalar 'AttrValue' as the right-hand side of an inspect
-- matcher. Compound values are not expected here; they would have been
-- rejected by validation.
renderInspectScalar :: AttrValue -> Doc ann
renderInspectScalar = \case
  AVText   t -> rubyString t
  AVNat    n -> pretty n
  AVBool   b -> if b then "true" else "false"
  AVSymbol s -> ":" <> pretty s
  v          -> pretty (showVal v)

-- | Phase 2 follow-up: split off the @file@ permission chain for one base
-- matcher (@readable@/@writable@/@executable@). Returns the chained Ruby
-- lines (zero, one, or two — for @_by_scope@ and @_by_user@ siblings) and
-- the attrs Map with the consumed keys removed. The bare flag is consumed
-- silently when any modifier is present, since @be_readable.by_user(u)@
-- already implies @be_readable@.
extractPermChain
  :: Text
  -> Map Text AttrValue
  -> ([Doc ann], Map Text AttrValue)
extractPermChain base attrs = (lines_, withoutKeys)
  where
    byScopeKey = base <> "_by_scope"
    byUserKey  = base <> "_by_user"
    byScope = case Map.lookup byScopeKey attrs of
      Just (AVSymbol s) -> Just $
        "it { should be_" <> pretty base
          <> ".by(:" <> pretty s <> ") }"
      _ -> Nothing
    byUser = case Map.lookup byUserKey attrs of
      Just (AVText u) -> Just $
        "it { should be_" <> pretty base
          <> ".by_user(" <> rubyString u <> ") }"
      _ -> Nothing
    bareLine = case (Map.lookup base attrs, byScope, byUser) of
      (Just (AVBool True), Nothing, Nothing) ->
        Just ("it { should be_" <> pretty base <> " }")
      _ -> Nothing
    lines_ = [ l | Just l <- [bareLine, byScope, byUser] ]
    withoutKeys = Map.delete base
                $ Map.delete byScopeKey
                $ Map.delete byUserKey
                  attrs

-- | Phase 2 follow-up: split off the @file@ contain chain. The base
-- @contains@ pattern is required; the modifiers (@.from@/@.to@/@.after@/
-- @.before@) chain off it. Returns @[]@ untouched if @contains@ is absent
-- so the unmodified attrs can flow through the default rendering.
extractContainsChain
  :: Map Text AttrValue
  -> ([Doc ann], Map Text AttrValue)
extractContainsChain attrs = case Map.lookup "contains" attrs of
  Just (AVText p) ->
    let from   = lookupText "contains_from"   attrs
        to_    = lookupText "contains_to"     attrs
        after_ = lookupText "contains_after"  attrs
        before = lookupText "contains_before" attrs
        line = case (from, to_, after_, before) of
          (Just f, Just t, _, _) ->
            "it { should contain(" <> rubyString p
              <> ").from(" <> rubyString f
              <> ").to("   <> rubyString t <> ") }"
          (Just f, Nothing, _, _) ->
            "it { should contain(" <> rubyString p
              <> ").from(" <> rubyString f <> ") }"
          (Nothing, Just t, _, _) ->
            "it { should contain(" <> rubyString p
              <> ").to(" <> rubyString t <> ") }"
          (_, _, Just a, _) ->
            "it { should contain(" <> rubyString p
              <> ").after(" <> rubyString a <> ") }"
          (_, _, _, Just b) ->
            "it { should contain(" <> rubyString p
              <> ").before(" <> rubyString b <> ") }"
          _ -> "it { should contain " <> rubyString p <> " }"
        rest = Map.delete "contains"
             $ Map.delete "contains_from"
             $ Map.delete "contains_to"
             $ Map.delete "contains_after"
             $ Map.delete "contains_before"
               attrs
    in ([line], rest)
  _ -> ([], attrs)

-- | Phase 2 follow-up: split off the @file@ mounted chain. Emits at most
-- the bare @be_mounted@ line plus one each of @.with(...)@ / @.only_with(...)@
-- (alphabetical order) and consumes the @be_mounted@ flag when any modifier
-- is present.
extractMountedChain
  :: Map Text AttrValue
  -> ([Doc ann], Map Text AttrValue)
extractMountedChain attrs = (lines_, rest)
  where
    onlyRec = case Map.lookup "mounted_only_with" attrs of
      Just (AVRecord kw) -> Just $
        "it { should be_mounted.only_with(" <> renderRecordKwargs kw <> ") }"
      _ -> Nothing
    withRec = case Map.lookup "mounted_with" attrs of
      Just (AVRecord kw) -> Just $
        "it { should be_mounted.with(" <> renderRecordKwargs kw <> ") }"
      _ -> Nothing
    bare = case (Map.lookup "be_mounted" attrs, onlyRec, withRec) of
      (Just (AVBool True), Nothing, Nothing) ->
        Just "it { should be_mounted }"
      _ -> Nothing
    lines_ = [ l | Just l <- [bare, onlyRec, withRec] ]
    rest = Map.delete "be_mounted"
         $ Map.delete "mounted_with"
         $ Map.delete "mounted_only_with"
           attrs

lookupText :: Text -> Map Text AttrValue -> Maybe Text
lookupText k m = case Map.lookup k m of
  Just (AVText t) -> Just t
  _               -> Nothing

-- | Render one merged 'Assertion' as a @describe ... do ... end@ block.
-- Singleton kinds (see 'singletonKinds') drop the @(<primaryKey>)@ argument.
-- The @php_config@ kind injects an @:ini => '<path>'@ keyword arg into the
-- header when the @_ini@ sentinel attribute is present (see Dhall
-- @phpConfigWithIni@).
formatGroup :: Assertion -> Either Text (Doc ann)
formatGroup (Assertion k pk attrs0 _) = do
  let resource = pretty (kindToRubyResource k)
      (iniArg, attrs)
        | k == "php_config"
        , Just (AVText p) <- Map.lookup "_ini" attrs0
        = (Just p, Map.delete "_ini" attrs0)
        | otherwise
        = (Nothing, attrs0)
  header <-
    if Set.member k singletonKinds
      then Right ("describe" <+> resource <+> "do")
      else do
        hd <- primaryDoc k pk
        let args = case iniArg of
              Nothing -> hd
              Just p  -> hd <> "," <+> ":ini" <+> "=>" <+> rubyString p
        Right ("describe" <+> resource <> "(" <> args <> ")" <+> "do")
  let body = vsep (renderAttrs k attrs)
  pure $ vsep [header, indent 2 body, "end"]

-- | Validate the @customAttributes@ list of a 'Node' before emitting any
-- @paninfraspec_<name> = ...@ preamble lines. Rejects:
--
--   * empty names or empty commands (both would produce broken Ruby);
--   * names that are not valid Ruby local-variable identifiers
--     (regex equivalent: @^[a-z_][a-zA-Z0-9_]*$@) — anything else would make
--     the generated @.rb@ file fail with @SyntaxError@ at runtime;
--   * duplicate names within the same node.
--
-- Returns the input list unchanged on success so callers can keep using the
-- declaration order.
validateCustomAttributes :: [CustomAttribute] -> Either Text [CustomAttribute]
validateCustomAttributes cas = do
  forM_ cas $ \ca -> do
    when (T.null (caName ca)) $
      Left "customAttribute name must be non-empty"
    when (T.null (caCommand ca)) $
      Left ("customAttribute command must be non-empty for: " <> caName ca)
    unless (isValidRubyLocal (caName ca)) $
      Left ("customAttribute name must be a valid Ruby local variable identifier: "
              <> caName ca)
  let names = map caName cas
      seen  = foldr collect (Right Set.empty) names
  case seen of
    Left dup -> Left ("duplicate customAttribute name: " <> dup)
    Right _  -> Right cas
  where
    collect _ (Left e)        = Left e
    collect n (Right s)
      | n `Set.member` s = Left n
      | otherwise        = Right (Set.insert n s)

    isValidRubyLocal :: Text -> Bool
    isValidRubyLocal t = case T.uncons t of
      Nothing      -> False
      Just (c, cs) ->
        (isAsciiLower c || c == '_')
          && T.all isIdentTail cs
      where
        isIdentTail c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '_'

-- | Render the preamble block placed between @require 'spec_helper'@ and the
-- first @describe@: one Ruby variable assignment per validated
-- 'CustomAttribute'.
renderCustomAttributePreamble :: [CustomAttribute] -> Doc ann
renderCustomAttributePreamble cas = vsep
  [ "paninfraspec_" <> pretty (caName ca)
      <+> "=" <+> "Specinfra.backend.run_command(" <> rubyString (caCommand ca) <> ").stdout.strip"
  | ca <- cas
  ]

-- | Render a 'Job' as one or more @(filename, content)@ pairs. Assertions
-- are partitioned by their module label so the same host can produce,
-- e.g., @Web/nginx_spec.rb@ and @Web/php_spec.rb@.
--
-- Order of operations: validate → group → merge (cross-module attribute
-- and module-label conflicts surface here) → partition by module → render.
-- Doing the merge BEFORE the partition is what preserves the
-- "exit-status=0 vs exit-status=1 for the same command" safety net even
-- when the conflicting commands sit in different module wrappers.
formatJob :: Layout -> Job -> Either Text [(FilePath, Text)]
formatJob layout (Job node assertions) = do
  validatedCAs <- validateCustomAttributes (customAttributes node)
  validated    <- traverse validateAssertion assertions
  merged       <- traverse mergeGroup (groupAssertions validated)
  let buckets = foldr addToBucket Map.empty merged
  traverse (renderBucket validatedCAs) (Map.toAscList buckets)
  where
    -- | Bucket merged assertions by module label. `foldr` + `Map.insertWith
    -- (++)` together preserve the original `(kind, primaryKey)` ordering
    -- inside each bucket, which keeps the rendered describe blocks stable
    -- for golden tests.
    addToBucket a = Map.insertWith (++) (aModule a) [a]

    renderBucket cas (maybeMod, asserts) = do
      blocks   <- traverse formatGroup asserts
      filename <- validateLayoutPath
                    (T.unpack (applySpecPath layout node maybeMod))
      let docText d = renderStrict (PP.layoutPretty PP.defaultLayoutOptions d)
          preambleLines
            | null cas  = []
            | otherwise = [docText (renderCustomAttributePreamble cas)]
          body = T.intercalate "\n\n"
                   ("require 'spec_helper'" : preambleLines ++ map docText blocks)
      pure (filename, body <> "\n")

-- | Top-level entry. Performs the backend guard, per-host emission with
-- collision detection (so a non-injective 'lSpecPath' fails fast), and
-- finally drops the scaffold-supplied static and inventory-derived files
-- in. Scaffold file paths must not collide with any spec output path or
-- with each other.
--
-- Note: 'sDerivedFiles' is fed only the nodes that survived plan
-- resolution (i.e. those that matched at least one mapping). Scaffolds
-- that need every node from the inventory regardless of assertions —
-- ansible_spec's @hosts@ is a candidate — should be invoked through
-- inventory pathways once that channel exists. For Phase 1 the per-job
-- node list is sufficient for both shipped scaffolds.
emit :: Scaffold -> Layout -> ExecutionPlan -> Either Text (Map FilePath Text)
emit scaffold layout ep
  | epTargetBackend ep /= "serverspec" =
      Left ("backend mismatch: expected serverspec, got " <> epTargetBackend ep)
  | otherwise = do
      perJob  <- traverse (formatJob layout) (epJobs ep)
      perHost <- foldM (insertSpec (lSharing layout)) Map.empty (concat perJob)
      let nodes  = jNode <$> epJobs ep
          extras = sStaticFiles scaffold
                ++ sDerivedFiles scaffold nodes
                ++ resolveBuiltinDerivers nodes (sBuiltinDerivers scaffold)
      foldM insertExtra perHost extras
  where
    -- PerHost: any path collision is a hard error (historic behaviour).
    -- PerRole: identical content collapses into one file (the role-shared
    -- spec); differing content is an error because the role-shared file
    -- cannot represent two distinct spec bodies. customAttributes are
    -- expanded into a preamble that runs against each host's Specinfra
    -- backend at runtime, so a role-shared file is fine as long as every
    -- host in the role declares the same customAttributes (same name and
    -- command, in the same order). Divergence shows up here as differing
    -- content.
    insertSpec PerHost acc (path, content) = case Map.lookup path acc of
      Just _  -> Left ("specPath collision at " <> T.pack path
                       <> ": multiple hosts mapped to the same output file")
      Nothing -> Right (Map.insert path content acc)
    insertSpec PerRole acc (path, content) = case Map.lookup path acc of
      Just existing
        | existing == content -> Right acc
        | otherwise           -> Left
            ("PerRole layout: hosts sharing " <> T.pack path
             <> " produced differing spec contents; ensure every host in the role"
             <> " gets the same assertions and the same customAttributes"
             <> " (matching name and command), or switch to a PerHost layout")
      Nothing -> Right (Map.insert path content acc)
    insertExtra acc OutputFile { ofPath = p, ofContent = c } = do
      validated <- validateLayoutPath (T.unpack p)
      case Map.lookup validated acc of
        Just _  -> Left ("scaffold file " <> p
                         <> " collides with a generated spec file or another scaffold file")
        Nothing -> Right (Map.insert validated c acc)
