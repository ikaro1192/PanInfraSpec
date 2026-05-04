-- dhall/Scaffold.dhall
-- Execution-scaffold prelude. A Scaffold bundles the auxiliary files that
-- accompany the per-host spec files so a runner (Serverspec, ansible_spec,
-- Goss, ...) can pick them up.
--
-- Backend-agnostic by design: future Goss / InSpec / Testinfra scaffolds
-- have no Rakefile concept, so this prelude does not hardcode "Rakefile" or
-- "spec_helper.rb" as fields. Instead a scaffold lists arbitrary
-- `staticFiles` (independent of inventory) and `derivedFiles` (computed
-- from the inventory). Backend-specific vocabulary lives in the shipped
-- prelude instances under `Scaffold/`.
--
-- File contents are plain `Text`. Use Dhall's `./path as Text` import to
-- pull a Rakefile / spec_helper.rb body from a sibling text file rather
-- than embedding the body as a Dhall multi-line literal.

let I = ./Inventory.dhall

let OutputFile : Type =
      { path    : Text
      , content : Text
      }

-- | Shipped, Haskell-rendered derivers. Use these for outputs whose
-- generation needs computation Dhall cannot express cheaply (e.g.
-- de-duplicating role names for an Ansible INI inventory requires Text
-- equality, which is only available via the Prelude). Each constructor
-- carries the relative path the rendered file should land at.
--
-- Custom derivations that *can* be expressed purely in Dhall belong in
-- `derivedFiles` instead — that field stays a free-form `List Node ->
-- List OutputFile` so users keep a programmable escape hatch.
let BuiltinDeriver : Type =
      < AnsibleHostsIni : { path : Text }
      | AnsibleSiteYml  : { path : Text }
      >

let ansibleHostsIni
    : Text -> BuiltinDeriver
    = \(p : Text) -> BuiltinDeriver.AnsibleHostsIni { path = p }

let ansibleSiteYml
    : Text -> BuiltinDeriver
    = \(p : Text) -> BuiltinDeriver.AnsibleSiteYml { path = p }

let Scaffold : Type =
      { name            : Text
      , staticFiles     : List OutputFile
      , derivedFiles    : List I.Node -> List OutputFile
      , builtinDerivers : List BuiltinDeriver
      }

let make
    : Scaffold -> Scaffold
    = \(s : Scaffold) -> s

in  { OutputFile      = OutputFile
    , BuiltinDeriver  = BuiltinDeriver
    , Scaffold        = Scaffold
    , make            = make
    , ansibleHostsIni = ansibleHostsIni
    , ansibleSiteYml  = ansibleSiteYml
    }
