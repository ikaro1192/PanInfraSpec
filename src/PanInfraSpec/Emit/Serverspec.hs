module PanInfraSpec.Emit.Serverspec
  ( emit
    -- * Schema (exported for property testing)
  , AttrTag (..)
  , serverspecSchema
  ) where

import Control.Monad (foldM, forM_, unless, when)
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
import Prettyprinter (Doc, indent, pretty, vsep, (<+>))
import qualified Prettyprinter as PP
import Prettyprinter.Render.Text (renderStrict)

import PanInfraSpec.IR

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
  , ("file", Map.fromList
      [ ("exist",        ATBool)
      , ("owned_by",     ATText)
      , ("grouped_into", ATText)
      , ("mode",         ATNat)
      , ("contains",     ATText)
      ])
  , ("command", Map.fromList
      [ ("exit-status", ATNat) ])
  , ("user", Map.fromList
      [ ("exist",            ATBool)
      , ("uid",              ATNat)
      , ("belongs_to_group", ATText)
      , ("home_directory",   ATText)
      , ("login_shell",      ATText)
      ])
  , ("group", Map.fromList
      [ ("exist", ATBool), ("gid", ATNat) ])
  , ("process", Map.fromList
      [ ("running", ATBool), ("user", ATText) ])
  , ("mount", Map.fromList
      [ ("mounted", ATBool)
      , ("device",  ATText)
      , ("fstype",  ATText)
      ])
  , ("interface", Map.fromList
      [ ("exist",        ATBool)
      , ("speed",        ATNat)
      , ("ipv4_address", ATText)
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
      [ ("resolvable", ATBool)
      , ("reachable",  ATBool)
      , ("ipaddress",  ATText)
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
      ])
  , ("linux_audit_system", Map.fromList
      [ ("running", ATBool)
      , ("enabled", ATBool)
      ])
  , ("linux_kernel_parameter", Map.fromList
      [ ("value", ATText) ])
  , ("cgroup", Map.empty)  -- wildcard kind: dynamic parameter names
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
validateAssertion a@(Assertion k pk attrs) = do
  kindSchema <- case Map.lookup k serverspecSchema of
    Just s  -> Right s
    Nothing -> Left ("unknown kind for serverspec: " <> k)
  when (Map.null attrs) $
    Left ("empty attrs for kind " <> k)
  forM_ (Map.toAscList attrs) $ \(key, val) ->
    if Map.null kindSchema
      then
        unless (tagOf val == ATText) $
          Left $ "wildcard kind " <> k <> " requires Text values; got "
              <> showTag (tagOf val) <> " for key " <> key
      else do
        expected <- case Map.lookup key kindSchema of
          Just t  -> Right t
          Nothing -> Left ("unknown attrs key for kind " <> k <> ": " <> key)
        let actual = tagOf val
        unless (actual == expected) $
          Left $ "wrong attr type for " <> k <> "." <> key
              <> ": expected " <> showTag expected <> ", got " <> showTag actual
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
-- guaranteed to fail at test time.
mergeGroup :: NonEmpty Assertion -> Either Text Assertion
mergeGroup (a :| rest) = foldM step a rest
  where
    step acc nxt = do
      merged <- mergeAttrs (aKind acc) (aPrimaryKey acc) (aAttrs acc) (aAttrs nxt)
      pure acc { aAttrs = merged }

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
-- command
formatItLine "command" "exit-status"      (AVNat n)  = "its(:exit_status) { should eq " <> pretty n <> " }"
-- user
formatItLine "user"    "exist"            _          = "it { should exist }"
formatItLine "user"    "uid"              (AVNat n)  = "it { should have_uid " <> pretty n <> " }"
formatItLine "user"    "belongs_to_group" (AVText g) = "it { should belong_to_group " <> rubyString g <> " }"
formatItLine "user"    "home_directory"   (AVText p) = "it { should have_home_directory " <> rubyString p <> " }"
formatItLine "user"    "login_shell"      (AVText s) = "it { should have_login_shell " <> rubyString s <> " }"
-- group
formatItLine "group"   "exist"            _          = "it { should exist }"
formatItLine "group"   "gid"              (AVNat n)  = "it { should have_gid " <> pretty n <> " }"
-- process
formatItLine "process" "running"          _          = "it { should be_running }"
formatItLine "process" "user"             (AVText u) = "its(:user) { should eq " <> rubyString u <> " }"
-- mount
formatItLine "mount"   "mounted"          _          = "it { should be_mounted }"
formatItLine "mount"   "device"           (AVText d) = "its(:device) { should eq " <> rubyString d <> " }"
formatItLine "mount"   "fstype"           (AVText t) = "its(:fstype) { should eq " <> rubyString t <> " }"
-- interface
formatItLine "interface" "exist"          _          = "it { should exist }"
formatItLine "interface" "speed"          (AVNat n)  = "its(:speed) { should eq " <> pretty n <> " }"
formatItLine "interface" "ipv4_address"   (AVText a) = "it { should have_ipv4_address " <> rubyString a <> " }"
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
formatItLine k key _ =
  "# UNREACHABLE: unmatched (" <> pretty k <> ", " <> pretty key <> ")"

-- | Map an IR @kind@ to the Ruby resource name used inside @describe@. Most
-- kinds map identically; @kernel-module@ becomes @kernel_module@ to match
-- Serverspec's Ruby identifier.
kindToRubyResource :: Text -> Text
kindToRubyResource = \case
  "kernel-module" -> "kernel_module"
  k               -> k

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
renderAttrs k attrs =
  [ formatItLine k key val | (key, val) <- Map.toAscList attrs ]

-- | Render one merged 'Assertion' as a @describe ... do ... end@ block.
-- Singleton kinds (see 'singletonKinds') drop the @(<primaryKey>)@ argument.
formatGroup :: Assertion -> Either Text (Doc ann)
formatGroup (Assertion k pk attrs) = do
  let resource = pretty (kindToRubyResource k)
  header <-
    if Set.member k singletonKinds
      then Right ("describe" <+> resource <+> "do")
      else do
        hd <- primaryDoc k pk
        Right ("describe" <+> resource <> "(" <> hd <> ")" <+> "do")
  let body = vsep (renderAttrs k attrs)
  pure $ vsep [header, indent 2 body, "end"]

-- | Render a 'Job' as a @(filename, content)@ pair.
formatJob :: Job -> Either Text (FilePath, Text)
formatJob (Job node assertions) = do
  validated <- traverse validateAssertion assertions
  merged    <- traverse mergeGroup (groupAssertions validated)
  blocks    <- traverse formatGroup merged
  let docText d = renderStrict (PP.layoutPretty PP.defaultLayoutOptions d)
      body      = T.intercalate "\n\n" ("require 'spec_helper'" : map docText blocks)
      filename  = T.unpack (hostname node) <> "_spec.rb"
  pure (filename, body <> "\n")

-- | Static @spec_helper.rb@ produced alongside each output set. Uses the
-- @:exec@ backend by default; tweak @TARGET_HOST@ in the environment to
-- switch to ssh transport without editing this file.
specHelperRb :: Text
specHelperRb = T.unlines
  [ "# Generated by paninfraspec-gen. Customise via environment, not in-place."
  , "require 'serverspec'"
  , ""
  , "if ENV['TARGET_HOST'].nil? || ENV['TARGET_HOST'].empty?"
  , "  set :backend, :exec"
  , "else"
  , "  require 'net/ssh'"
  , "  set :backend, :ssh"
  , "  set :host, ENV['TARGET_HOST']"
  , "  set :ssh_options, Net::SSH::Config.for(ENV['TARGET_HOST'])"
  , "  set :request_pty, true"
  , "end"
  , ""
  , "RSpec.configure do |c|"
  , "  c.color    = true"
  , "  c.formatter = :documentation"
  , "end"
  ]

-- | Static @Rakefile@ wired to run all generated @*_spec.rb@ files. Uses
-- @Rake::FileList@ so empty directories raise loudly instead of silently
-- matching nothing.
rakefile :: Text
rakefile = T.unlines
  [ "# Generated by paninfraspec-gen."
  , "require 'rake'"
  , "require 'rspec/core/rake_task'"
  , ""
  , "specs = Rake::FileList['*_spec.rb']"
  , ""
  , "if specs.empty?"
  , "  abort 'no *_spec.rb files found in this directory'"
  , "end"
  , ""
  , "RSpec::Core::RakeTask.new(:spec) do |t|"
  , "  t.pattern    = specs"
  , "  t.rspec_opts = '--format documentation --color'"
  , "end"
  , ""
  , "task default: :spec"
  ]

-- | Top-level entry. Performs the backend guard and assembles per-host Ruby
-- files plus the static helpers.
emit :: ExecutionPlan -> Either Text (Map FilePath Text)
emit ep
  | epTargetBackend ep /= "serverspec" =
      Left ("backend mismatch: expected serverspec, got " <> epTargetBackend ep)
  | otherwise = do
      pairs <- traverse formatJob (epJobs ep)
      let perHost = Map.fromList pairs
      pure $ Map.insert "spec_helper.rb" specHelperRb
           $ Map.insert "Rakefile"       rakefile perHost
