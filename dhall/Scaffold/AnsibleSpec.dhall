-- dhall/Scaffold/AnsibleSpec.dhall
-- Shipped ansible_spec scaffold. Generates the auxiliary `hosts` (Ansible
-- INI inventory) and `site.yml` (group → roles playbook) alongside a
-- Rakefile that invokes the ansible_spec gem.
--
-- Why `builtinDerivers` instead of `derivedFiles`: rendering an Ansible
-- INI inventory needs to de-duplicate role names, which requires Text
-- equality. Dhall has no built-in `Text/equal`; the Prelude version pulls
-- in a non-trivial dependency chain. Pushing the work to Haskell via
-- `builtinDerivers` keeps the shipped scaffold self-contained and the
-- backend-agnostic `Scaffold` type tidy. Users who need a custom shape can
-- still drop a Dhall function into `derivedFiles` (it is left empty here).
--
-- Group derivation: each distinct PanInfraSpec role becomes one Ansible
-- group; the role name is used verbatim as the group name. Tag-derived
-- groups are out of scope for the shipped scaffold — fork this Dhall file
-- and override `derivedFiles` if you need them.
--
-- Module label → Ansible role name: PanInfraSpec's module label
-- (`Spec.module_ "nginx" […]`) maps to an Ansible role of the same name.
-- The site.yml produced here lists no roles per group (`roles: []`); the
-- Rakefile globs `spec/<group>/*_spec.rb` directly, so the playbook entry
-- only needs to surface the group, not enumerate roles. Fork the scaffold
-- if you need a populated `roles:` list.
--
-- The shipped `L.ansibleSpec` layout produces the matching
-- `spec/<group>/<module>_spec.rb` shape; pair it with this scaffold via
-- `--layout`.

let S = ../Scaffold.dhall
let I = ../Inventory.dhall

in  S.make
      { name            = "ansible_spec"
      , staticFiles     =
          [ { path    = "Rakefile"
            , content = ./AnsibleSpec/Rakefile.template as Text
            }
          , { path    = "spec_helper.rb"
            , content = ./AnsibleSpec/spec_helper.rb.template as Text
            }
          ]
      , derivedFiles    = \(_ : List I.Node) -> [] : List S.OutputFile
      , builtinDerivers =
          [ S.ansibleHostsIni "hosts"
          , S.ansibleSiteYml  "site.yml"
          ]
      }
