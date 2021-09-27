module Component.ConfirmInput (render) where

import Prologue hiding (div)
import Component.Amount (amount)
import Component.Box (box)
import Component.Box as Box
import Component.Button (button)
import Component.Button.Types as Button
import Component.Column (column)
import Component.Column as Column
import Component.ConfirmInput.Types (Input)
import Component.Expand as Expand
import Component.Heading (Preset(..), heading)
import Component.IconButton (iconButton)
import Component.Link (link)
import Component.Row (row)
import Component.Row as Row
import Component.Transfer (transfer)
import Component.Transfer.Types (Account(..), Owner(..), Transfer(..), Wallet(..)) as Transfer
import Contacts.State (getAda)
import Contract.State (currentStep, toInput)
import Contract.Types (Action(..))
import Data.Array (fromFoldable)
import Data.Default (default)
import Data.Foldable (length)
import Data.List as List
import Data.Map as Map
import Data.Set as Set
import Data.Symbol (SProxy(..))
import Halogen (ComponentHTML)
import Halogen.Css (classNames)
import Halogen.HTML (HTML, div, div_, lazy, p, slot, span, text)
import MainFrame.Types (ChildSlots)
import Marlowe.Execution.State (mkTx)
import Marlowe.Execution.Types (NamedAction(..))
import Marlowe.Semantics (ChoiceId(..), Contract(..), Party, Payee(..), Payment(..), TransactionOutput(..)) as Semantics
import Marlowe.Semantics (Token(..), computeTransaction)
import Material.Icons (icon_)
import Material.Icons as Icon

render :: forall m. Monad m => Input -> ComponentHTML Action ChildSlots m
render =
  lazy \input@{ action, contractState } ->
    let
      stepNumber = currentStep contractState + 1
    in
      column Column.Divided [ "h-full", "grid", "grid-rows-auto-1fr-auto" ]
        [ sectionBox [ "lg:p-5" ]
            $ heading H2 [ "leading-none" ]
                [ text
                    $ "Step "
                    <> show stepNumber
                    <> " "
                    <> case action of
                        MakeDeposit _ _ _ _ -> "deposit"
                        MakeChoice _ _ _ -> "choice"
                        CloseContract -> "close"
                        _ -> ""
                ]
        , summary input
        , confirmation input
        ]

summary :: forall m. Monad m => Input -> ComponentHTML Action ChildSlots m
summary input@{ action } =
  sectionBox [ "overflow-y-scroll" ]
    $ column Column.Divided [ "space-y-4" ]
        [ column default []
            [ heading H3 []
                [ text
                    $ case action of
                        MakeDeposit _ _ _ _ -> "Deposit"
                        MakeChoice _ _ _ -> "Choice"
                        CloseContract -> "Close"
                        _ -> ""
                    <> " summary"
                ]
            , box Box.Card [] case action of
                MakeDeposit recipient sender _ amount ->
                  transfer
                    $ Transfer.WalletToAccount
                        (Transfer.Wallet sender $ toOwner input sender)
                        (Transfer.Account recipient $ toOwner input recipient)
                        amount
                MakeChoice (Semantics.ChoiceId key _) _ _ ->
                  row Row.Between []
                    [ span [ classNames [ "font-semibold", "text-sm" ] ]
                        [ text "Your choice:" ]
                    , span [ classNames [ "font-semibold", "text-sm" ] ]
                        [ text key ]
                    ]
                CloseContract ->
                  row default []
                    [ span [ classNames [ "font-semibold", "text-sm" ] ]
                        [ text "You a closing the contract" ]
                    ]
                _ -> text ""
            ]
        , box Box.NoSpace [ "pt-4" ]
            $ slot
                (SProxy :: _ "expandSlot")
                "resultingActions"
                Expand.component
                { initial: Expand.Closed
                , render: \{ toggle, state } -> rusults input toggle state
                }
                (const Nothing)
        ]

rusults :: forall w i. Input -> i -> Expand.State -> HTML w i
rusults input@{ action, contractState, currentSlot } toggle = case _ of
  Expand.Opened ->
    layout Icon.ExpandLess
      $ box Box.Card []
      <$> (fromFoldable $ payment <$> payments)
      <> if willClose then
          [ row Row.Between []
              [ text "Contract finishes"
              , icon_ Icon.Task
              ]
          ]
        else
          []
  Expand.Closed -> layout Icon.ExpandMore []
  where
  layout icon children =
    column Column.Snug []
      $ [ row Row.Between [ "items-center" ]
            [ heading H4 [] [ text $ show count <> " resulting actions" ]
            , iconButton icon $ Just toggle
            ]
        ]
      <> children

  payment (Semantics.Payment sender payee money) =
    transfer case payee of
      Semantics.Party recipient ->
        Transfer.AccountToWallet
          (Transfer.Account sender $ toOwner input recipient)
          (Transfer.Wallet recipient $ toOwner input recipient)
          $ getAda money
      Semantics.Account recipient ->
        Transfer.AccountToAccount
          (Transfer.Account sender $ toOwner input recipient)
          (Transfer.Account recipient $ toOwner input recipient)
          $ getAda money

  contract = contractState.executionState.contract

  semanticState = contractState.executionState.semanticState

  txInput =
    mkTx currentSlot contract $ List.fromFoldable
      $ toInput
      $ action

  txOutput = computeTransaction txInput semanticState contract

  payments = case txOutput of
    Semantics.TransactionOutput { txOutPayments } -> fromFoldable txOutPayments
    _ -> []

  willClose = case txOutput of
    Semantics.TransactionOutput { txOutContract } -> txOutContract == Semantics.Close
    _ -> input.action == CloseContract

  count = length payments + if willClose then 1 else 0

toOwner :: Input -> Semantics.Party -> Transfer.Owner
toOwner { contractState: { participants, userParties }, userNickname } party =
  if Set.member party userParties then
    Transfer.CurrentUser userNickname
  else
    Transfer.OtherUser $ join $ Map.lookup party $ participants

confirmation :: forall w. Input -> HTML w Action
confirmation { action, transactionFeeQuote, walletBalance } =
  column Column.Divided []
    [ sectionBox [ "bg-lightgray" ]
        $ row Row.Between []
            [ span [ classNames [ "font-semibold", "text-sm" ] ] [ text "Wallet balance:" ]
            , amount (Token "" "") walletBalance [ "text-sm" ]
            ]
    , sectionBox []
        $ column default []
            [ div_
                [ heading H4 [ "font-semibold" ]
                    [ text "Confirm payment of" ]
                , p [ classNames [ "text-xs", "leading-none" ] ]
                    [ amount (Token "" "") total [ "text-2xl", "text-purple" ]
                    ]
                , p [ classNames [ "text-xxs", "opacity-50" ] ]
                    [ text "Transaction fee: ~"
                    , amount (Token "" "") transactionFeeQuote [ "text-xxs" ]
                    ]
                ]
            , div [ classNames [ "grid", "grid-cols-2", "gap-4" ] ]
                [ button
                    Button.Secondary
                    (Just $ CancelConfirmation)
                    []
                    [ text "Cancel" ]
                , button
                    Button.Primary
                    (Just $ ConfirmAction action)
                    []
                    [ text "Confirm" ]
                ]
            ]
    , sectionBox []
        $ p [ classNames [ "text-xs" ] ]
            [ text "*Transaction fees are estimates only and are shown in completed contract steps "
            , link
                "https://docs.cardano.org/explore-cardano/fee-structure"
                []
                [ text "Read more in Docs" ]
            , text "."
            ]
    ]
  where
  total =
    transactionFeeQuote
      + case action of
          MakeDeposit _ _ _ amount -> amount
          _ -> zero

sectionBox :: forall i w. Array String -> HTML i w -> HTML i w
sectionBox css = box default $ [ "lg:px-5" ] <> css