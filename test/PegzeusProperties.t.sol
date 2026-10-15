// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Pegzeus} from "../src/Pegzeus.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PegzeusTestSupport} from "./helpers/PegzeusTestSupport.sol";

/// @notice Boundary and algebraic properties supplementing the existing deployment/ERC-20 tests.
/// forge-config: default.fuzz.runs = 1000
contract PegzeusPropertiesTest is PegzeusTestSupport {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    Pegzeus private token;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Pegzeus();
    }

    function test_oneBaseUnitMakesAnExactRoundTrip() public {
        require(token.transfer(ALICE, 1), "first leg");
        vm.prank(ALICE);
        require(token.transfer(BOB, 1), "second leg");
        vm.prank(BOB);
        require(token.transfer(address(this), 1), "return leg");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_fullSupplyDelegatedTransferCannotBeRepeated() public {
        require(token.approve(SPENDER, SUPPLY), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, SUPPLY), "full supply spend");
        require(token.allowance(address(this), SPENDER) == 0, "allowance not exhausted");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        _assertBalances(0, SUPPLY, 0);
    }

    function test_maximumTransferFailsWithoutOverflowOrStateChange() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_almostMaximumAllowanceIsFinite() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1), "spend one base unit");
        require(token.allowance(address(this), SPENDER) == type(uint256).max - 2, "finite allowance not spent");
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_infiniteAllowanceCannotBypassBalanceChecks() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "failed spend changed allowance");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroAmountDoesNotMakeZeroRecipientValid() public {
        token.approve(SPENDER, 1);
        bytes memory errorData = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        vm.expectRevert(errorData);
        token.transfer(address(0), 0);
        vm.expectRevert(errorData);
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        require(token.allowance(address(this), SPENDER) == 1, "zero transfer changed approval");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(ALICE, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutMovingBalances() public {
        token.approve(SPENDER, 7);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), address(this), 4), "delegated self-transfer");
        require(token.allowance(address(this), SPENDER) == 3, "self-transfer bypassed spending");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 3, 4));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(this), 4);
        require(token.allowance(address(this), SPENDER) == 3, "failed self-transfer spent allowance");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_ownerTransferFromRequiresSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        token.approve(address(this), 1);
        require(token.transferFrom(address(this), ALICE, 1), "self-approved spend");
        require(token.allowance(address(this), address(this)) == 0, "self-approval not exhausted");
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_infiniteApprovalCanBeReplacedAndRevoked() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1), "infinite spend");
        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1), "replacement spend");
        require(token.allowance(address(this), SPENDER) == 1, "replacement not finite");
        token.approve(SPENDER, type(uint256).max);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        require(token.allowance(address(this), SPENDER) == 0, "infinite approval survived revocation");
        _assertBalances(SUPPLY - 2, 2, 0);
    }

    function test_approvalDoesNotReserveFundsAndSurvivesFailedSpend() public {
        token.approve(SPENDER, 10);
        require(token.transfer(ALICE, SUPPLY), "owner can move approved funds");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 10);
        require(token.allowance(address(this), SPENDER) == 10, "failed spend consumed approval");
        vm.prank(ALICE);
        require(token.transfer(address(this), 10), "refill");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, 10), "original allowance remains usable");
        require(token.allowance(address(this), SPENDER) == 0, "allowance not consumed");
        _assertBalances(0, SUPPLY - 10, 10);
    }

    function testFuzz_roundTripReturnsEveryBaseUnit(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        require(token.transfer(ALICE, amount), "outbound transfer");
        require(token.balanceOf(ALICE) == amount, "outbound amount");
        vm.prank(ALICE);
        require(token.transfer(address(this), amount), "return transfer");
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_splittingTransferDoesNotChangeOutcome(uint256 rawTotal, uint256 rawFirst) public {
        uint256 total = bound(rawTotal, 0, SUPPLY);
        uint256 first = bound(rawFirst, 0, total);
        Pegzeus singleTransferToken = new Pegzeus();
        require(singleTransferToken.transfer(ALICE, total), "single transfer");
        require(token.transfer(ALICE, first), "first part");
        require(token.transfer(ALICE, total - first), "second part");
        require(token.balanceOf(ALICE) == singleTransferToken.balanceOf(ALICE), "split changed recipient amount");
        require(
            token.balanceOf(address(this)) == singleTransferToken.balanceOf(address(this)), "split changed sender debit"
        );
        _assertBalances(SUPPLY - total, total, 0);
    }

    function testFuzz_insufficientBalancePreservesAllowanceAndBalances(
        uint256 rawBalance,
        uint256 rawAmount,
        uint256 rawAllowance
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        uint256 allowed = bound(rawAllowance, amount, type(uint256).max);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        require(token.allowance(ALICE, SPENDER) == allowed, "failed spend consumed allowance");
        _assertBalances(SUPPLY - balance, balance, 0);
    }

    function testFuzz_insufficientAllowancePreservesFundsEvenWithEnoughBalance(
        uint256 rawBalance,
        uint256 rawAllowance,
        uint256 rawAmount
    ) public {
        uint256 balance = bound(rawBalance, 1, SUPPLY);
        uint256 allowed = bound(rawAllowance, 0, balance - 1);
        uint256 amount = bound(rawAmount, allowed + 1, balance);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowed, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        require(token.allowance(ALICE, SPENDER) == allowed, "rejected spend changed allowance");
        _assertBalances(SUPPLY - balance, balance, 0);
    }

    function testFuzz_invalidRecipientRollsBackAnyAllowance(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 allowed = bound(rawAllowance, amount, type(uint256).max);
        token.approve(SPENDER, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), amount);
        require(token.allowance(address(this), SPENDER) == allowed, "invalid receiver consumed allowance");
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_approvalsAreIsolatedAndCannotMoveFunds(uint256 first, uint256 replacement, uint256 unrelated)
        public
    {
        token.transfer(ALICE, 1);
        token.approve(SPENDER, first);
        token.approve(BOB, unrelated);
        vm.prank(ALICE);
        token.approve(SPENDER, unrelated);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, replacement);
        require(token.approve(SPENDER, replacement), "replacement approval");
        require(token.allowance(address(this), SPENDER) == replacement, "approval did not replace");
        require(token.allowance(address(this), BOB) == unrelated, "different spender affected");
        require(token.allowance(ALICE, SPENDER) == unrelated, "different owner affected");
        require(token.allowance(SPENDER, address(this)) == 0, "approval became reciprocal");
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function testFuzz_revokedAllowanceCannotBeUsed(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowed = bound(rawAllowance, 1, type(uint256).max);
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        token.approve(SPENDER, allowed);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, amount));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        require(token.allowance(address(this), SPENDER) == 0, "revocation not preserved");
        _assertBalances(SUPPLY, 0, 0);
    }

    function _assertBalances(uint256 deployerBalance, uint256 aliceBalance, uint256 bobBalance) private view {
        require(token.balanceOf(address(this)) == deployerBalance, "deployer balance");
        require(token.balanceOf(ALICE) == aliceBalance, "alice balance");
        require(token.balanceOf(BOB) == bobBalance, "bob balance");
        require(token.balanceOf(SPENDER) == 0, "spender acquired tokens");
        require(token.balanceOf(address(0)) == 0, "tokens burned to zero");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }
}
