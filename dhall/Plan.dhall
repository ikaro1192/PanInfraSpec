-- dhall/Plan.dhall
-- Selector and Mapping prelude. Backend-agnostic in shape, but pulls Assertion
-- from the chosen backend prelude.

let Selector =
      < SelAll
      | SelRole : Text
      | SelTag  : Text
      | SelHost : Text
      >

let Spec = ./Serverspec.dhall

let Mapping = { selector : Selector, assertions : List Spec.Assertion }

let onAll =
      \(xs : List Spec.Assertion) ->
        { selector = Selector.SelAll, assertions = xs } : Mapping

let forRole =
      \(r : Text) ->
      \(xs : List Spec.Assertion) ->
        { selector = Selector.SelRole r, assertions = xs } : Mapping

let forTag =
      \(t : Text) ->
      \(xs : List Spec.Assertion) ->
        { selector = Selector.SelTag t, assertions = xs } : Mapping

let forHost =
      \(h : Text) ->
      \(xs : List Spec.Assertion) ->
        { selector = Selector.SelHost h, assertions = xs } : Mapping

let Plan : Type = { targetBackend : Text, mappings : List Mapping }

let make =
      \(targetBackend : Text) ->
      \(mappings : List Mapping) ->
        { targetBackend = targetBackend, mappings = mappings } : Plan

in  { Selector = Selector
    , Mapping  = Mapping
    , Plan     = Plan
    , onAll    = onAll
    , forRole  = forRole
    , forTag   = forTag
    , forHost  = forHost
    , make     = make
    }
