// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Pegzeus} from "../src/Pegzeus.sol";
import {PegzeusHandler} from "./handlers/PegzeusHandler.sol";
import {PegzeusTestSupport} from "./helpers/PegzeusTestSupport.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PegzeusInvariantTest is PegzeusTestSupport {
    PegzeusHandler private handler;
    Pegzeus private token;

    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        handler = new PegzeusHandler();
        token = handler.token();
    }

    /// @dev Foundry's standard targeting ABI, kept local to avoid a new dependency/remapping.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = PegzeusHandler.transfer.selector;
        selectors[1] = PegzeusHandler.approve.selector;
        selectors[2] = PegzeusHandler.transferFrom.selector;
        selectors[3] = PegzeusHandler.transferOverBalance.selector;
        selectors[4] = PegzeusHandler.attemptTransferFrom.selector;
        selectors[5] = PegzeusHandler.invalidRecipient.selector;
        selectors[6] = PegzeusHandler.invalidSpender.selector;
        selectors[7] = PegzeusHandler.forbiddenControl.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariant_supplyAndMetadataNeverChange() public view {
        require(token.totalSupply() == SUPPLY, "fixed supply changed");
        require(token.INITIAL_SUPPLY() == SUPPLY, "supply constant differs from specification");
        require(token.decimals() == 18, "decimals changed");
        require(keccak256(bytes(token.name())) == keccak256("Pegzeus"), "name changed");
        require(keccak256(bytes(token.symbol())) == keccak256("PEGZ"), "symbol changed");
        require(token.balanceOf(address(0)) == 0, "zero address received tokens");
    }

    function invariant_balancesMatchAuthorizedFlowsAndSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            require(balance == handler.expectedBalance(actor), "holder balance disagrees with ledger");
            sum += balance;
        }
        uint256 heldByToken = token.balanceOf(address(token));
        require(heldByToken == handler.expectedBalance(address(token)), "contract balance disagrees with ledger");
        require(sum + heldByToken == SUPPLY, "balances do not conserve supply");
        require(token.balanceOf(address(this)) == 0, "test caller received a constructor allocation");
    }

    function invariant_allowancesMatchOwnerAuthorizations() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            require(token.allowance(owner, address(0)) == 0, "zero spender acquired allowance");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                require(
                    token.allowance(owner, spender) == handler.expectedAllowance(owner, spender),
                    "allowance disagrees with owner authorization"
                );
            }
        }
    }

    /// @dev Deterministically proves the handler reaches positive transfers and checked failures.
    function test_handlerExercisesStateChangesAndRejections() public {
        handler.transfer(0, 1, 1, false);
        handler.approve(1, 2, 10, 2);
        handler.transferFrom(1, 2, 3, 4, false);
        handler.attemptTransferFrom(1, 2, 0, 0, 1); // Seven requested, six approved.
        handler.approve(1, 2, 0, 1); // Infinite allowance.
        handler.transferFrom(1, 2, 1, 1, false); // Delegated self-transfer.
        handler.invalidRecipient(1, 2, 1, true);
        handler.attemptTransferFrom(1, 2, 0, 0, 0); // Enough allowance, insufficient balance.
        handler.approve(1, 2, 0, 0); // Revoke the infinite approval.
        handler.attemptTransferFrom(1, 2, 0, 1, 2);
        handler.transferOverBalance(0, 1, type(uint256).max);
        handler.invalidSpender(0, type(uint256).max);
        handler.forbiddenControl(0, 1, 1, 0);
        handler.transfer(3, 4, 0, true); // Include tokens held by the token itself.

        require(handler.successfulTransfers() == 2, "no direct transfer coverage");
        require(handler.successfulDelegatedTransfers() == 2, "no delegated transfer coverage");
        require(handler.successfulApprovals() == 3, "no approval coverage");
        require(handler.rejectedCalls() == 7, "no rejection coverage");
        invariant_supplyAndMetadataNeverChange();
        invariant_balancesMatchAuthorizedFlowsAndSumToSupply();
        invariant_allowancesMatchOwnerAuthorizations();
    }
}
